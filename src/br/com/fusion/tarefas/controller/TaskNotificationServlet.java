package br.com.fusion.tarefas.controller;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import jakarta.mail.Authenticator;
import jakarta.mail.Message;
import jakarta.mail.PasswordAuthentication;
import jakarta.mail.Session;
import jakarta.mail.Transport;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import br.com.fusion.tarefas.config.AppConfig;
import br.com.fusion.tarefas.model.DestinatarioNotificacao;
import br.com.fusion.tarefas.model.ResultadoEnvioNotificacao;
import br.com.fusion.tarefas.model.TarefaNotificacao;
import br.com.fusion.tarefas.repository.TarefaRepository;
import br.com.fusion.tarefas.security.Autorizacao;

/**
 * Endpoint de notificação de tarefas atrasadas.
 *
 * GET  /custom/task-notification  -> verificação de saúde (requer autenticação).
 * POST /custom/task-notification  -> envia notificação (requer autenticação,
 *                                     pertencer ao grupo administrador e
 *                                     requisição same-origin).
 */
@WebServlet(
    name = "TaskNotificationServlet",
    urlPatterns = { "/custom/task-notification" },
    loadOnStartup = 1
)
public class TaskNotificationServlet extends HttpServlet {

    private static final long serialVersionUID = 1L;

    private transient TarefaRepository repository;
    private transient AppConfig config;

    @Override
    public void init() throws ServletException {
        try {
            String caminho = System.getProperty("fusion.config.path");

            if (caminho == null || caminho.trim().isEmpty()) {
                throw new IllegalStateException(
                    "Propriedade de sistema fusion.config.path não definida."
                );
            }

            config = new AppConfig(Path.of(caminho.trim()));
            repository = new TarefaRepository(config);
        } catch (Exception e) {
            throw new ServletException(
                "Não foi possível carregar a configuração do Fusion Tarefas.",
                e
            );
        }
    }

    @Override
    protected void doGet(
            HttpServletRequest request,
            HttpServletResponse response) throws IOException {

        if (identificarUsuario(request) == null) {
            responderErro(
                response,
                HttpServletResponse.SC_UNAUTHORIZED,
                "Autenticação necessária."
            );
            return;
        }

        responderJson(
            response,
            HttpServletResponse.SC_OK,
            "{\"success\":true,"
                + "\"message\":\"Endpoint funcionando\"}"
        );
    }

    @Override
    protected void doPost(
            HttpServletRequest request,
            HttpServletResponse response) throws IOException {

        try {
            String usuario = identificarUsuario(request);

            if (usuario == null) {
                responderErro(
                    response,
                    HttpServletResponse.SC_UNAUTHORIZED,
                    "Autenticação necessária."
                );
                return;
            }

            if (!Autorizacao.ehAdministrador(config, usuario)) {
                getServletContext().log(
                    "TASK_NOTIFICATION_ACESSO_NEGADO usuario=" + usuario
                );
                responderErro(
                    response,
                    HttpServletResponse.SC_FORBIDDEN,
                    "Acesso não autorizado."
                );
                return;
            }

            if (!requisicaoSameOrigin(request)) {
                getServletContext().log(
                    "TASK_NOTIFICATION_CSRF_BLOQUEADO usuario=" + usuario
                );
                responderErro(
                    response,
                    HttpServletResponse.SC_FORBIDDEN,
                    "Requisição não autorizada."
                );
                return;
            }

            List<Long> ids = lerIds(request);

            if (ids.isEmpty()) {
                responderErro(
                    response,
                    HttpServletResponse.SC_BAD_REQUEST,
                    "Nenhuma tarefa foi informada."
                );
                return;
            }

            int encontradas = 0;
            int enviadas = 0;
            List<String> falhas = new ArrayList<>();

            for (Long id : ids) {
                try {
                    TarefaNotificacao tarefa =
                        repository.buscarPorTaskInstanceId(id);

                    if (tarefa == null) {
                        falhas.add(rotulo(id) + ": tarefa não encontrada");
                        continue;
                    }

                    encontradas++;

                    ResultadoEnvioNotificacao resultado =
                        enviarEmail(tarefa);

                    if (resultado.getAceitas() > 0) {
                        enviadas++;
                    }

                    for (String falha : resultado.getFalhas()) {
                        falhas.add(rotulo(id) + ": " + falha);
                    }
                } catch (Exception e) {
                    getServletContext().log(
                        "TASK_NOTIFICATION_ERROR taskInstanceId=" + id,
                        e
                    );
                    falhas.add(
                        rotulo(id) + ": falha ao processar a notificação"
                    );
                }
            }

            if (encontradas == 0) {
                responderErro(
                    response,
                    HttpServletResponse.SC_NOT_FOUND,
                    "Nenhuma tarefa foi encontrada. "
                        + String.join("; ", falhas)
                );
                return;
            }

            if (enviadas == 0) {
                responderErro(
                    response,
                    HttpServletResponse.SC_BAD_REQUEST,
                    String.join("; ", falhas)
                );
                return;
            }

            responderSucesso(response, ids.size(), enviadas, falhas);
        } catch (NumberFormatException e) {
            responderErro(
                response,
                HttpServletResponse.SC_BAD_REQUEST,
                "taskInstanceId inválido."
            );
        } catch (Exception e) {
            getServletContext().log(
                "Erro ao processar a notificação de tarefa.",
                e
            );

            responderErro(
                response,
                HttpServletResponse.SC_INTERNAL_SERVER_ERROR,
                "Erro ao processar a solicitação."
            );
        }
    }

    private String identificarUsuario(HttpServletRequest request) {
        return Autorizacao.identificarUsuario(
            request,
            request.getSession(false)
        );
    }

    /**
     * Mitigação de CSRF baseada em cabeçalho personalizado e verificação de
     * origem. O JavaScript da aplicação envia X-Requested-With; navegadores não
     * permitem definir esse cabeçalho em requisições cross-site simples sem
     * preflight CORS.
     */
    private boolean requisicaoSameOrigin(HttpServletRequest request) {
        String xrw = request.getHeader("X-Requested-With");

        if (xrw == null || !"XMLHttpRequest".equalsIgnoreCase(xrw.trim())) {
            return false;
        }

        String origin = request.getHeader("Origin");

        if (origin != null && !origin.trim().isEmpty()) {
            String host = hostDe(origin);

            if (host == null
                    || !host.equalsIgnoreCase(request.getServerName())) {
                return false;
            }
        }

        String referer = request.getHeader("Referer");

        if (referer != null && !referer.trim().isEmpty()) {
            String host = hostDe(referer);

            if (host != null
                    && !host.equalsIgnoreCase(request.getServerName())) {
                return false;
            }
        }

        return true;
    }

    private String hostDe(String url) {
        try {
            return URI.create(url.trim()).getHost();
        } catch (Exception e) {
            return null;
        }
    }

    private ResultadoEnvioNotificacao enviarEmail(
            TarefaNotificacao tarefa) throws Exception {

        ResultadoEnvioNotificacao resultado =
            new ResultadoEnvioNotificacao();

        List<DestinatarioNotificacao> destinatarios =
            repository.obterDestinatariosComNome(tarefa);

        if (destinatarios.isEmpty()) {
            resultado.registrarFalha(
                "nenhum destinatário possui e-mail válido"
            );
            return resultado;
        }

        String host = config.required("smtp.host");
        String port = config.required("smtp.port");
        String username = config.required("smtp.username");
        String password = config.required("smtp.password");
        String from = config.required("smtp.from");
        String fromName = config.optional("smtp.from.name", "Fusion");

        Properties props = new Properties();
        props.put("mail.smtp.host", host);
        props.put("mail.smtp.port", port);
        props.put("mail.smtp.auth", "true");
        props.put("mail.smtp.starttls.enable", "true");
        props.put("mail.smtp.starttls.required", "true");

        Session session = Session.getInstance(props, new Authenticator() {
            @Override
            protected PasswordAuthentication getPasswordAuthentication() {
                return new PasswordAuthentication(username, password);
            }
        });

        String baseUrl = config.required("fusion.url");

        for (DestinatarioNotificacao destinatario : destinatarios) {
            try {
                MimeMessage message = new MimeMessage(session);
                message.setFrom(
                    new InternetAddress(from, fromName, "UTF-8")
                );
                message.setRecipient(
                    Message.RecipientType.TO,
                    new InternetAddress(destinatario.getEmail(), true)
                );
                message.setSubject(
                    "Tarefa atrasada no Fusion",
                    "UTF-8"
                );
                message.setContent(
                    construirHtml(
                        tarefa,
                        destinatario.getNome(),
                        baseUrl
                    ),
                    "text/html; charset=UTF-8"
                );

                Transport.send(message);
                resultado.registrarAceita();
            } catch (Exception e) {
                resultado.registrarFalha(
                    "falha no envio do e-mail"
                );
                getServletContext().log(
                    "TASK_NOTIFICATION_SEND_ERROR taskInstanceId="
                        + tarefa.getTaskInstanceId()
                        + " recipient=" + destinatario.getEmail(),
                    e
                );
            }
        }

        return resultado;
    }

    private String construirHtml(
        TarefaNotificacao tarefa,
        String nomeDestinatario,
        String baseUrl) {

        String solicitacao = escapeHtml(tarefa.getProtocolo());
        String processo = escapeHtml(tarefa.getProcesso());
        String nomeTarefa = escapeHtml(tarefa.getTarefa());
        String diasAtraso = escapeHtml(tarefa.getDiasAtraso());
        String dataPrazo = escapeHtml(tarefa.getVencimento());
        String responsavel = escapeHtml(nomeDestinatario);
        String urlTarefa = construirUrlTarefa(
            tarefa.getTaskInstanceId(),
            baseUrl
        );

        if (responsavel.trim().isEmpty()) {
            responsavel = "equipe responsável";
        }

        return "<!DOCTYPE html>"
            + "<html lang=\"pt-BR\"><body style=\"margin:0;padding:0;"
            + "background:#f2f4f7;font-family:Arial,Helvetica,sans-serif;\">"
            + "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"background:#f2f4f7;padding:28px 10px;\">"
            + "<tr><td align=\"center\">"
            + "<table role=\"presentation\" width=\"620\" cellpadding=\"0\" cellspacing=\"0\" style=\"max-width:620px;width:100%;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 5px 18px rgba(0,0,0,.10);\">"
            + "<tr><td style=\"height:6px;background:#1d6fa8;font-size:0;line-height:0;\">&nbsp;</td></tr>"
            + "<tr><td style=\"padding:24px 34px 4px;\">"
            + "<p style=\"margin:0;font-size:18px;line-height:26px;font-weight:bold;color:#202124;\">Fusion Tarefas</p>"
            + "</td></tr>"
            + "<tr><td style=\"padding:24px 34px 30px;color:#262626;\">"
            + "<p style=\"margin:0 0 8px;font-size:20px;line-height:28px;font-weight:bold;color:#202124;\">Olá, " + responsavel + ".</p>"
            + "<p style=\"margin:0 0 25px;font-size:14px;line-height:22px;color:#667085;\">Existe uma tarefa atrasada que precisa da sua atenção.</p>"
            + "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"border:1px solid #e4e7ec;border-radius:9px;overflow:hidden;\">"
            + linhaEmail("Nº da Solicitação", solicitacao)
            + linhaEmail("Processo", processo)
            + linhaEmail("Tarefa", nomeTarefa)
            + linhaEmail("Dias de Atraso", diasAtraso)
            + linhaEmail("Data prazo", dataPrazo)
            + "</table>"
            + "<p style=\"margin:25px 0 0;font-size:14px;line-height:22px;color:#667085;\">Favor verificar a atividade no Fusion.</p>"
            + botaoVerTarefa(urlTarefa)
            + "</td></tr>"
            + "<tr><td align=\"center\" style=\"background:#262626;padding:24px 20px 22px;\">"
            + "<p style=\"margin:0;color:#bfc3c8;font-size:11px;line-height:17px;\">"
            + "Esta é uma mensagem automática. Não responda a este e-mail."
            + "</p>"
            + "</td></tr></table></td></tr></table></body></html>";
    }

    private String construirUrlTarefa(Long taskInstanceId, String baseUrl) {
        if (taskInstanceId == null) {
            return "";
        }

        String linkInterno = "portal/render/Task"
            + "?type=Task"
            + "&showSummaryBtn=true"
            + "&take=false"
            + "&taskInstanceId=" + taskInstanceId
            + "&edit=true"
            + "&readOnly=false"
            + "&boxname=user_active_tasks"
            + "&showTaskCloseBtn=true"
            + "&forcedBreadcrumb=true"
            + "&from=3"
            + "&fromemail=true"
            + "&setCurrentSideBar=true";

        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }

        return baseUrl
            + "/rest/redirect/mail/link?link="
            + URLEncoder.encode(linkInterno, StandardCharsets.UTF_8);
    }

    private String botaoVerTarefa(String urlTarefa) {
        if (urlTarefa == null || urlTarefa.trim().isEmpty()) {
            return "";
        }

        return "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" style=\"margin:27px auto 0;\"><tr><td align=\"center\" style=\"border-radius:7px;background:#1d6fa8;box-shadow:0 4px 9px rgba(21,84,125,.25);\">"
            + "<a href=\"" + escapeHtml(urlTarefa) + "\" target=\"_blank\" style=\"display:inline-block;padding:14px 21px;border:1px solid #15547d;border-radius:7px;color:#fff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;line-height:20px;text-decoration:none;\">Ver tarefa no Fusion&nbsp;&nbsp;<span style=\"font-size:17px;\">&#8594;</span></a>"
            + "</td></tr></table>";
    }

    private String linhaEmail(String titulo, String valor) {
        String conteudo = valor == null || valor.trim().isEmpty()
            ? "-"
            : valor;

        return "<tr>"
            + "<td style=\"width:42%;padding:14px 15px;border-bottom:1px solid #eef0f2;font-size:12px;font-weight:bold;color:#667085;background:#fafbfc;\">"
            + escapeHtml(titulo)
            + "</td>"
            + "<td style=\"padding:14px 15px;border-bottom:1px solid #eef0f2;font-size:13px;color:#262626;\">"
            + conteudo
            + "</td></tr>";
    }

    private String escapeHtml(Object value) {
        if (value == null) {
            return "";
        }

        return String.valueOf(value)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&#39;");
    }

    private String rotulo(Long id) {
        return "tarefa " + id;
    }

    private List<Long> lerIds(HttpServletRequest request) {
        List<Long> ids = new ArrayList<>();
        String valor = request.getParameter("taskInstanceId");

        if (valor == null || valor.trim().isEmpty()) {
            return ids;
        }

        valor = valor.trim();

        if (!valor.matches("\\d{1,18}")) {
            throw new NumberFormatException("taskInstanceId inválido.");
        }

        long id = Long.parseLong(valor);

        if (id <= 0) {
            throw new NumberFormatException("taskInstanceId inválido.");
        }

        ids.add(id);
        return ids;
    }

    private void responderSucesso(
            HttpServletResponse response,
            int total,
            int enviadas,
            List<String> falhas) throws IOException {

        String mensagem = falhas.isEmpty()
            ? "Notificação enviada com sucesso"
            : "Notificações enviadas com algumas falhas";

        responderJson(
            response,
            HttpServletResponse.SC_OK,
            "{\"success\":true,"
                + "\"sucesso\":true,"
                + "\"total\":" + total + ","
                + "\"enviadas\":" + enviadas + ","
                + "\"falhas\":" + falhas.size() + ","
                + "\"message\":\"" + escJson(mensagem) + "\"}"
        );
    }

    private void responderErro(
            HttpServletResponse response,
            int status,
            String mensagem) throws IOException {
        responderJson(
            response,
            status,
            "{\"success\":false,\"message\":\""
                + escJson(mensagem)
                + "\"}"
        );
    }

    private void responderJson(
            HttpServletResponse response,
            int status,
            String json) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(json);
    }

    private String escJson(String value) {
        if (value == null) {
            return "";
        }

        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\r", "\\r")
            .replace("\n", "\\n");
    }
}
