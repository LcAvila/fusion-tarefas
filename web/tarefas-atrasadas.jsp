<%@ page language="java" contentType="text/html; charset=UTF-8"
    pageEncoding="UTF-8" session="true"%>

<%@ page import="java.sql.Connection"%>
<%@ page import="java.sql.PreparedStatement"%>
<%@ page import="java.sql.ResultSet"%>
<%@ page import="java.util.ArrayList"%>
<%@ page import="java.util.LinkedHashMap"%>
<%@ page import="java.util.List"%>
<%@ page import="java.util.Map"%>
<%@ page import="java.util.Set"%>
<%@ page import="java.util.TreeSet"%>
<%@ page import="br.com.fusion.tarefas.security.Autorizacao"%>
<%@ page import="jakarta.servlet.http.HttpServletResponse"%>
<%@ page import="java.nio.file.Paths"%>
<%@ page import="br.com.fusion.tarefas.config.AppConfig"%>
<%@ page import="br.com.fusion.tarefas.config.BancoDados"%>
<%@ page import="br.com.fusion.tarefas.repository.TarefasSql"%>

<%!
private AppConfig carregarConfig() throws Exception {
    String caminho = System.getProperty("fusion.config.path");

    if (caminho == null || caminho.trim().isEmpty()) {
        throw new IllegalStateException(
            "Propriedade de sistema fusion.config.path não definida."
        );
    }

    return new AppConfig(Paths.get(caminho.trim()));
}

private Connection conectar() throws Exception {
    return BancoDados.conectar(carregarConfig());
}

/* A montagem do SQL e a vinculação de parâmetros ficaram centralizadas em
 * br.com.fusion.tarefas.repository.TarefasSql, que isola as diferenças entre
 * MySQL e PostgreSQL (funções de data, valor nulo e predicado de "ativo"). */

private int contarTotal(
        String tipo,
        String solicitante, String processo, String nomeTarefa,
        String dataInicio, String dataFim,
        Integer atrasoMin, Integer atrasoMax) throws Exception {

    TarefasSql.Consulta consulta = TarefasSql.contar(
        tipo, solicitante, processo, nomeTarefa,
        dataInicio, dataFim, atrasoMin, atrasoMax);

    try (Connection connection = conectar();
         PreparedStatement statement =
             connection.prepareStatement(consulta.getSql())) {
        TarefasSql.aplicar(statement, consulta.getParametros());

        try (ResultSet resultSet = statement.executeQuery()) {
            return resultSet.next() ? resultSet.getInt("total") : 0;
        }
    }
}

private List<Map<String, String>> consultar(
        String tipo,
        String solicitante, String processo, String nomeTarefa,
        String dataInicio, String dataFim,
        Integer atrasoMin, Integer atrasoMax,
        int limite, int offset) throws Exception {

    TarefasSql.Consulta consulta = TarefasSql.listar(
        tipo, solicitante, processo, nomeTarefa,
        dataInicio, dataFim, atrasoMin, atrasoMax, limite, offset);

    List<Map<String, String>> lista = new ArrayList<>();

    try (Connection connection = conectar();
         PreparedStatement statement =
             connection.prepareStatement(consulta.getSql())) {
        TarefasSql.aplicar(statement, consulta.getParametros());

        try (ResultSet resultSet = statement.executeQuery()) {
            while (resultSet.next()) {
                Map<String, String> item = new LinkedHashMap<>();
                item.put("task_id", resultSet.getString("task_id"));
                item.put("task_instance_id",
    		    resultSet.getString("task_instance_id"));
                item.put("activity_id", resultSet.getString("activity_id"));
                item.put("protocolo", resultSet.getString("protocolo"));
                item.put("processo", resultSet.getString("processo"));
                item.put("solicitante", resultSet.getString("solicitante"));
                item.put("tarefa", resultSet.getString("tarefa"));
                item.put("responsavel", resultSet.getString("responsavel"));
                item.put("responsavel_neoId",
                    resultSet.getString("responsavel_neoId"));
                item.put("email_responsavel",
                    resultSet.getString("email_responsavel"));
                item.put("data_solicitacao",
                    resultSet.getString("data_solicitacao"));
                item.put("data_vencimento",
                    resultSet.getString("data_vencimento"));
                item.put("dias_atraso",
                    resultSet.getString("dias_atraso"));
                item.put("descricao", resultSet.getString("descricao"));
                lista.add(item);
            }
        }
    }

    return lista;
}

private Set<String> valoresDistintos(
        String tipo, String coluna) throws Exception {
    Set<String> valores = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);

    TarefasSql.Consulta consulta = TarefasSql.valoresDistintos(tipo, coluna);

    try (Connection connection = conectar();
         PreparedStatement statement =
             connection.prepareStatement(consulta.getSql());
         ResultSet resultSet = statement.executeQuery()) {

        while (resultSet.next()) {
            String valor = resultSet.getString("valor");
            if (valor != null && !valor.trim().isEmpty()) {
                valores.add(valor.trim());
            }
        }
    }

    return valores;
}

private String esc(String valor) {
    if (valor == null) return "";

    return valor.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;");
}

private String classeAtraso(String valor) {
    try {
        int dias = Integer.parseInt(valor);
        if (dias >= 30) return "critical";
        if (dias >= 7) return "warning";
        return "attention";
    } catch (Exception e) {
        return "attention";
    }
}
%>

<%
request.setCharacterEncoding("UTF-8");

String identificadorUsuario =
    Autorizacao.identificarUsuario(request, session);

if (identificadorUsuario == null
        || identificadorUsuario.trim().isEmpty()) {
    response.sendError(
        HttpServletResponse.SC_UNAUTHORIZED,
        "É necessário estar autenticado no Fusion para acessar este relatório."
    );
    return;
}

try {
    if (!Autorizacao.ehAdministrador(
            carregarConfig(),
            identificadorUsuario)) {
        response.sendError(
            HttpServletResponse.SC_FORBIDDEN,
            "Acesso permitido somente para administradores do grupo admG."
        );
        return;
    }
} catch (Exception e) {
    application.log("ERRO_AUTORIZACAO_JSP: " + e.getMessage(), e);
    response.sendError(
        HttpServletResponse.SC_INTERNAL_SERVER_ERROR,
        "Não foi possível validar a autorização do usuário."
    );
    return;
}

String solicitante = request.getParameter("solicitante");
String processo = request.getParameter("processo");
String nomeTarefa = request.getParameter("nomeTarefa");
String dataInicio = request.getParameter("dataInicio");
String dataFim = request.getParameter("dataFim");
String atrasoMinParam = request.getParameter("atrasoMin");
String atrasoMaxParam = request.getParameter("atrasoMax");
String paginaParam = request.getParameter("pagina");

if (solicitante == null) solicitante = "";
if (processo == null) processo = "";
if (nomeTarefa == null) nomeTarefa = "";
if (dataInicio == null) dataInicio = "";
if (dataFim == null) dataFim = "";
if (atrasoMinParam == null) atrasoMinParam = "";
if (atrasoMaxParam == null) atrasoMaxParam = "";

final int tamanhoPagina = 20;
int paginaAtual = 1;
Integer atrasoMin = null;
Integer atrasoMax = null;
String tipo = null;
String erro = null;

List<Map<String, String>> tarefas = new ArrayList<>();
Set<String> solicitantes = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
Set<String> processos = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
Set<String> tarefasDisponiveis =
    new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
int totalRegistros = 0;
int totalPaginas = 1;

try {
    if (!atrasoMinParam.trim().isEmpty()) {
        atrasoMin = Integer.valueOf(atrasoMinParam.trim());
    }

    if (!atrasoMaxParam.trim().isEmpty()) {
        atrasoMax = Integer.valueOf(atrasoMaxParam.trim());
    }

    if (atrasoMin != null && atrasoMin < 0) {
        throw new IllegalArgumentException(
            "O atraso mínimo não pode ser negativo."
        );
    }

    if (atrasoMax != null && atrasoMax < 0) {
        throw new IllegalArgumentException(
            "O atraso máximo não pode ser negativo."
        );
    }

    if (atrasoMin != null && atrasoMax != null
            && atrasoMin > atrasoMax) {
        throw new IllegalArgumentException(
            "O atraso mínimo não pode ser maior que o atraso máximo."
        );
    }

    if (!dataInicio.trim().isEmpty()) java.sql.Date.valueOf(dataInicio);
    if (!dataFim.trim().isEmpty()) java.sql.Date.valueOf(dataFim);

    if (!dataInicio.trim().isEmpty() && !dataFim.trim().isEmpty()
            && dataInicio.compareTo(dataFim) > 0) {
        throw new IllegalArgumentException(
            "A data inicial não pode ser posterior à data final."
        );
    }

    if (paginaParam != null && !paginaParam.trim().isEmpty()) {
        try {
            paginaAtual = Integer.parseInt(paginaParam.trim());
        } catch (Exception ignorado) {
            paginaAtual = 1;
        }
    }

    if (paginaAtual < 1) paginaAtual = 1;

    tipo = BancoDados.tipo(carregarConfig());

    totalRegistros = contarTotal(
        tipo, solicitante, processo, nomeTarefa,
        dataInicio, dataFim, atrasoMin, atrasoMax
    );

    totalPaginas = (int) Math.ceil(
        totalRegistros / (double) tamanhoPagina
    );

    if (totalPaginas < 1) totalPaginas = 1;
    if (paginaAtual > totalPaginas) paginaAtual = totalPaginas;

    tarefas = consultar(
        tipo, solicitante, processo, nomeTarefa,
        dataInicio, dataFim, atrasoMin, atrasoMax,
        tamanhoPagina, (paginaAtual - 1) * tamanhoPagina
    );

    solicitantes = valoresDistintos(tipo, "U_REQ.fullname");
    processos = valoresDistintos(tipo, "PM.title");
    tarefasDisponiveis = valoresDistintos(tipo, "TI.taskName");
} catch (Exception e) {
    erro = e.getMessage();
    if (erro == null || erro.trim().isEmpty()) {
        erro = e.getClass().getSimpleName();
    }
    application.log("ERRO_CONSULTA_TAREFAS: " + erro, e);
}

String queryFiltros =
    "solicitante=" + java.net.URLEncoder.encode(solicitante, "UTF-8")
    + "&processo=" + java.net.URLEncoder.encode(processo, "UTF-8")
    + "&nomeTarefa=" + java.net.URLEncoder.encode(nomeTarefa, "UTF-8")
    + "&dataInicio=" + java.net.URLEncoder.encode(dataInicio, "UTF-8")
    + "&dataFim=" + java.net.URLEncoder.encode(dataFim, "UTF-8")
    + "&atrasoMin=" + java.net.URLEncoder.encode(atrasoMinParam, "UTF-8")
    + "&atrasoMax=" + java.net.URLEncoder.encode(atrasoMaxParam, "UTF-8");

String contextPath = request.getContextPath();
%>

<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tarefas atrasadas - Fusion</title>
    <link rel="stylesheet"
          href="<%= contextPath %>/custom/fusion-tarefas/css/style.css?v=20260924-23">
</head>
<body>
<main class="page">
    <section class="shell">
<header class="header">
    <h1>Central de tarefas atrasadas</h1>

<button class="icon-button refresh-button"
        type="button"
        id="btnAtualizarLista"
        aria-label="Atualizar lista"
        title="Atualizar lista">
    <svg viewBox="0 0 24 24"
         aria-hidden="true">
        <path d="M12,2a10.032,10.032,0,0,1,7.122,3H15V7h5.143A1.859,1.859,0,0,0,22,5.143V0H20V3.078A11.982,11.982,0,0,0,0,12H2A10.011,10.011,0,0,1,12,2Z"/>
        <path d="M22,12A9.986,9.986,0,0,1,4.878,19H9V17H3.857A1.859,1.859,0,0,0,2,18.857V24H4V20.922A11.982,11.982,0,0,0,24,12Z"/>
    </svg>
</button>

</header>

        <section>
            <div class="filters-top">
                <div>
                    <strong>Filtros</strong>
                    <div class="subtitle">Refine a consulta quando necessário.</div>
                </div>

                <div class="filters-top-actions">
                    <span><%= totalRegistros %> resultado(s)</span>
<button class="button button-light filter-toggle"
        id="toggleFiltros"
        type="button"
        aria-expanded="false"
        aria-controls="corpoFiltros"
        aria-label="Mostrar filtros"
        title="Mostrar filtros">
<svg id="iconeFiltros"
         viewBox="0 0 24 24"
         aria-hidden="true">
<path d="M22.586,5.929l-9.879,9.879a1.021,1.021,0,0,1-1.414,0L1.42,5.934.006,7.348l9.873,9.874a3.075,3.075,0,0,0,4.243,0L24,7.343Z"/>
</svg>
</button>
                </div>
            </div>

            <div class="filter-body" id="corpoFiltros" hidden>
                <form method="get" action="<%= request.getRequestURI() %>">
                    <div class="filter-grid">
                        <div>
                            <label for="solicitante">Solicitante</label>
                            <input class="input" id="solicitante"
                                   name="solicitante"
                                   list="listaSolicitantes"
                                   value="<%= esc(solicitante) %>">
                        </div>

                        <div>
                            <label for="processo">Nome do processo</label>
                            <input class="input" id="processo"
                                   name="processo"
                                   list="listaProcessos"
                                   value="<%= esc(processo) %>">
                        </div>

                        <div>
                            <label for="nomeTarefa">Nome da tarefa</label>
                            <input class="input" id="nomeTarefa"
                                   name="nomeTarefa"
                                   list="listaTarefas"
                                   value="<%= esc(nomeTarefa) %>">
                        </div>

                        <div>
                            <label for="dataInicio">Data inicial</label>
                            <input class="input" id="dataInicio"
                                   name="dataInicio" type="date"
                                   value="<%= esc(dataInicio) %>">
                        </div>

                        <div>
                            <label for="dataFim">Data final</label>
                            <input class="input" id="dataFim"
                                   name="dataFim" type="date"
                                   value="<%= esc(dataFim) %>">
                        </div>

                        <div>
                            <label for="atrasoMin">Atraso mínimo</label>
                            <input class="input" id="atrasoMin"
                                   name="atrasoMin" type="number" min="0"
                                   value="<%= esc(atrasoMinParam) %>">
                        </div>

                        <div>
                            <label for="atrasoMax">Atraso máximo</label>
                            <input class="input" id="atrasoMax"
                                   name="atrasoMax" type="number" min="0"
                                   value="<%= esc(atrasoMaxParam) %>">
                        </div>
                    </div>

                    <div class="filter-actions">
                        <a class="button button-light"
                           href="<%= request.getRequestURI() %>">Limpar</a>
                        <button class="button button-primary" type="submit">
                            Aplicar filtros
                        </button>
                    </div>
                </form>
            </div>
        </section>
    </section>

    <datalist id="listaSolicitantes">
        <% for (String opcao : solicitantes) { %>
            <option value="<%= esc(opcao) %>"></option>
        <% } %>
    </datalist>

    <datalist id="listaProcessos">
        <% for (String opcao : processos) { %>
            <option value="<%= esc(opcao) %>"></option>
        <% } %>
    </datalist>

    <datalist id="listaTarefas">
        <% for (String opcao : tarefasDisponiveis) { %>
            <option value="<%= esc(opcao) %>"></option>
        <% } %>
    </datalist>

    <% if (erro != null) { %>
        <div class="error is-visible">
            Não foi possível consultar as tarefas atrasadas.<br><br>
            <%= esc(erro) %>
        </div>
    <% } else if (tarefas.isEmpty()) { %>
        <div class="shell empty">Nenhuma tarefa atrasada encontrada.</div>
    <% } else { %>
        <section class="shell">
            <div class="toolbar">
                <div class="toolbar-left">
                    <input id="selecionarTodos" type="checkbox">
                    <label for="selecionarTodos">
                        Selecionar todos desta página
                    </label>
                    <span id="selecionadosInfo">0 selecionada(s)</span>
                </div>

                <button class="button button-primary" type="button"
                        id="btnNotificarSelecionadas">
                    Notificar selecionadas
                </button>
            </div>

            <div id="resultadoNotificacao" role="status"
                 aria-live="polite" style="display:none;"></div>

            <div class="table-wrapper">
                <table id="tabelaTarefas">
                    <thead>
                        <tr>
                            <th></th>
                            <th>N° da Solicitação</th>
                            <th>Processo</th>
                            <th>Solicitante</th>
                            <th>Tarefa</th>
                            <th>Responsável</th>
                            <th>Solicitação</th>
                            <th>Atraso</th>
                            <th>Ações</th>
                        </tr>
                    </thead>
                    <tbody>
                    <% for (Map<String, String> tarefa : tarefas) {
                        String dias = tarefa.get("dias_atraso");
                        String classe = classeAtraso(dias);
                    %>
                        <tr data-task-instance-id="<%= esc(tarefa.get("task_instance_id")) %>"
                            data-task-id="<%= esc(tarefa.get("task_id")) %>"
                            data-activity-id="<%= esc(tarefa.get("activity_id")) %>"
                            data-processo="<%= esc(tarefa.get("processo")) %>"
                            data-solicitante="<%= esc(tarefa.get("solicitante")) %>"
                            data-protocolo="<%= esc(tarefa.get("protocolo")) %>"
                            data-tarefa="<%= esc(tarefa.get("tarefa")) %>"
                            data-responsavel="<%= esc(tarefa.get("responsavel")) %>"
                            data-email="<%= esc(tarefa.get("email_responsavel")) %>"
                            data-data-solicitacao="<%= esc(tarefa.get("data_solicitacao")) %>"
                            data-vencimento="<%= esc(tarefa.get("data_vencimento")) %>"
                            data-dias-atraso="<%= esc(dias) %>"
                            data-descricao="<%= esc(tarefa.get("descricao")) %>">

                            <td class="selection-cell" data-label="">
                                <input class="row-select" type="checkbox">
                            </td>
                            <td class="code" data-label="N° da Solicitação">
                                <%= esc(tarefa.get("protocolo")) %>
                            </td>
                            <td data-label="Processo">
                                <%= esc(tarefa.get("processo")) %>
                            </td>
                            <td data-label="Solicitante">
                                <%= esc(tarefa.get("solicitante")) %>
                            </td>
                            <td data-label="Tarefa">
                                <%= esc(tarefa.get("tarefa")) %>
                            </td>
                            <td data-label="Responsável">
                                <%= esc(tarefa.get("responsavel")) %>
                            </td>
                            <td data-label="Solicitação">
                                <%= esc(tarefa.get("data_solicitacao")) %>
                            </td>
                            <td data-label="Atraso">
                                <span class="badge badge-<%= classe %>">
                                    <%= esc(dias) %> dia(s)
                                </span>
                            </td>
                            <td class="actions" data-label="Ações">

<button class="button button-light"
        type="button"
        data-acao="ver-tarefa">
    Ver tarefa
</button>

                                <button class="button button-light" type="button"
                                        data-acao="detalhar">
                                    Detalhar
                                </button>
                                <button class="button button-notify" type="button"
                                        data-acao="notificar">
                                    Notificar
                                </button>
                            </td>
                        </tr>
                    <% } %>
                    </tbody>
                </table>
            </div>

            <div class="pagination">
                <span class="pagination-info">
                    Página <%= paginaAtual %> de <%= totalPaginas %>
                    — <%= totalRegistros %> registro(s)
                </span>
                <nav class="pagination-nav">
                    <% if (paginaAtual > 1) { %>
                        <a href="?<%= queryFiltros %>&pagina=<%= paginaAtual - 1 %>">Anterior</a>
                    <% } else { %>
                        <span>Anterior</span>
                    <% } %>

                    <% int inicio = Math.max(1, paginaAtual - 2); %>
                    <% int fim = Math.min(totalPaginas, paginaAtual + 2); %>

                    <% for (int p = inicio; p <= fim; p++) { %>
                        <% if (p == paginaAtual) { %>
                            <span class="current"><%= p %></span>
                        <% } else { %>
                            <a href="?<%= queryFiltros %>&pagina=<%= p %>"><%= p %></a>
                        <% } %>
                    <% } %>

                    <% if (paginaAtual < totalPaginas) { %>
                        <a href="?<%= queryFiltros %>&pagina=<%= paginaAtual + 1 %>">Próxima</a>
                    <% } else { %>
                        <span>Próxima</span>
                    <% } %>
                </nav>
            </div>
        </section>
    <% } %>
</main>
<div id="modalDetalhes"
     class="modal-backdrop"
     role="presentation">

    <section class="modal"
             role="dialog"
             aria-modal="true"
             aria-labelledby="tituloModalDetalhes">

        <header class="modal-header">
            <h2 id="tituloModalDetalhes">
                Detalhes da tarefa
            </h2>

            <button class="close"
                    type="button"
                    id="btnFecharModal"
                    aria-label="Fechar">
                &times;
            </button>
        </header>

        <div class="modal-body">
            <div class="detail">
                <span class="detail-label">Processo</span>
                <span id="detProcesso"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Solicitante</span>
                <span id="detSolicitante"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">N° da Solicitação</span>
                <span id="detProtocolo"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Tarefa</span>
                <span id="detTarefa"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Responsável</span>
                <span id="detResponsavel"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Solicitação</span>
                <span id="detDataSolicitacao"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Vencimento</span>
                <span id="detVencimento"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">Dias de atraso</span>
                <span id="detDiasAtraso"
                      class="detail-value"></span>
            </div>

            <div class="detail">
                <span class="detail-label">E-mail</span>
                <span id="detEmail"
                      class="detail-value"></span>
            </div>

            <div class="detail full">
                <span class="detail-label">Descrição</span>
                <span id="detDescricao"
                      class="detail-value"></span>
            </div>
        </div>

        <footer class="modal-footer">
            <button class="button button-light"
                    type="button"
                    id="btnFecharModalRodape">
                Fechar
            </button>

            <button class="button button-notify"
                    type="button"
                    id="btnNotificarModal">
                Notificar
            </button>
        </footer>

    </section>
</div>

<script>
    window.FUSION_TAREFAS_CONTEXT_PATH = "<%= contextPath %>";
</script>
<script src="<%= contextPath %>/custom/fusion-tarefas/script/script.js?v=20260924-24"></script>
</body>
</html>
