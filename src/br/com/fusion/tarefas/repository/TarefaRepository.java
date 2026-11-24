package br.com.fusion.tarefas.repository;

import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.Map;

import br.com.fusion.tarefas.config.AppConfig;
import br.com.fusion.tarefas.config.BancoDados;
import br.com.fusion.tarefas.model.TarefaNotificacao;
import br.com.fusion.tarefas.model.DestinatarioNotificacao;

public class TarefaRepository {

    private final AppConfig config;
    private final String tipoBanco;

    public TarefaRepository(AppConfig config) {
        this.config = config;
        this.tipoBanco = BancoDados.tipo(config);
    }

    public TarefaRepository(Path arquivoConfig) throws Exception {
        this(new AppConfig(arquivoConfig));
    }

    private Connection conectar() throws Exception {
        return BancoDados.conectar(config);
    }

    public TarefaNotificacao buscarPorTaskInstanceId(
            Long taskInstanceId) throws Exception {

        if (taskInstanceId == null) {
            throw new IllegalArgumentException(
                "taskInstanceId não pode ser nulo"
            );
        }

        String sql =
            "SELECT "
          + "TI.id AS taskInstanceId, "
          + "TI.task_neoId AS taskId, "
          + "TI.activity_neoId AS activityId, "
          + "PM.title AS processo, "
          + "WFP.code AS protocolo, "
          + "TI.taskName AS tarefa, "
          + "UATUAL.neoId AS responsavelId, "
          + "UATUAL.fullname AS responsavel, "
          + "UATUAL.email AS email, "
          + "TI.dueDate AS vencimento, "
          + BancoDados.diasAtraso(tipoBanco, "TI.dueDate") + " AS diasAtraso "
          + "FROM taskinstance TI "
          + "INNER JOIN wfprocess WFP "
          + "ON WFP.neoId = TI.processId "
          + "INNER JOIN processmodel PM "
          + "ON PM.neoId = WFP.model_neoId "
          + "LEFT JOIN neouser UATUAL "
          + "ON UATUAL.neoId = TI.owner_neoId "
          + "WHERE TI.id = ?";

        try (Connection connection = conectar();
             PreparedStatement statement =
                 connection.prepareStatement(sql)) {

            statement.setLong(1, taskInstanceId);

            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    return null;
                }

                TarefaNotificacao tarefa =
                    new TarefaNotificacao();

                tarefa.setTaskInstanceId(
                    obterLong(resultSet, "taskInstanceId")
                );
                tarefa.setTaskId(
                    obterLong(resultSet, "taskId")
                );
                tarefa.setActivityId(
                    obterLong(resultSet, "activityId")
                );
                tarefa.setProcesso(
                    resultSet.getString("processo")
                );
                tarefa.setProtocolo(
                    resultSet.getString("protocolo")
                );
                tarefa.setTarefa(
                    resultSet.getString("tarefa")
                );
                tarefa.setResponsavelId(
                    obterLong(resultSet, "responsavelId")
                );
                tarefa.setResponsavel(
                    resultSet.getString("responsavel")
                );
                tarefa.setEmail(
                    resultSet.getString("email")
                );
                tarefa.setVencimento(
                    resultSet.getString("vencimento")
                );
                tarefa.setDiasAtraso(
                    obterInteger(resultSet, "diasAtraso")
                );

                return tarefa;
            }
        }
    }

    /*
     * Use este método depois que os nomes reais das tabelas da pool
     * forem confirmados no banco. Não execute uma SQL presumida.
     */
    public List<String> buscarEmailsDaPool(
            Long taskInstanceId) throws Exception {

        if (taskInstanceId == null) {
            return new ArrayList<>();
        }

        String sql =
            "SELECT DISTINCT U.email "
          + "FROM taskinstance TI "
          + "INNER JOIN activity A "
          + "ON A.neoId = TI.activity_neoId "
          + "INNER JOIN activitymodel AM "
          + "ON AM.neoId = A.model_neoId "
          + "INNER JOIN roletaskassigner_roleset RTA "
          + "ON RTA.RoleTaskAssigner_neoId = AM.taskAssigner_neoId "
          + "INNER JOIN neouser U "
          + "ON U.group_neoId = RTA.roleSet_neoId "
          + "WHERE TI.id = ? "
          + "AND U.email IS NOT NULL "
          + "AND TRIM(U.email) <> ''";

        Set<String> emails = new LinkedHashSet<>();

        try (Connection connection = conectar();
             PreparedStatement statement =
                 connection.prepareStatement(sql)) {

            statement.setLong(1, taskInstanceId);

            try (ResultSet resultSet = statement.executeQuery()) {
                while (resultSet.next()) {
                    adicionarEmail(
                        emails,
                        resultSet.getString("email")
                    );
                }
            }
        }

        return new ArrayList<>(emails);
    }

public List<DestinatarioNotificacao> obterDestinatariosComNome(
        TarefaNotificacao tarefa) throws Exception {

    Map<String, DestinatarioNotificacao> porEmail =
        new LinkedHashMap<>();

    Set<String> emailIndividual = new LinkedHashSet<>();
    adicionarEmail(emailIndividual, tarefa.getEmail());

    if (!emailIndividual.isEmpty()) {
        String email = emailIndividual.iterator().next();

        porEmail.put(
            email,
            new DestinatarioNotificacao(
                tarefa.getResponsavel(),
                email
            )
        );

        return new ArrayList<>(porEmail.values());
    }

    if (tarefa.getTaskInstanceId() == null) {
        return new ArrayList<>();
    }

    String sql =
        "SELECT DISTINCT U.fullname, U.email "
      + "FROM taskinstance TI "
      + "INNER JOIN activity A "
      + "ON A.neoId = TI.activity_neoId "
      + "INNER JOIN activitymodel AM "
      + "ON AM.neoId = A.model_neoId "
      + "INNER JOIN roletaskassigner_roleset RTA "
      + "ON RTA.RoleTaskAssigner_neoId = AM.taskAssigner_neoId "
      + "INNER JOIN neouser U "
      + "ON U.group_neoId = RTA.roleSet_neoId "
      + "WHERE TI.id = ? "
      + "AND U.email IS NOT NULL "
      + "AND TRIM(U.email) <> ''";

    try (Connection connection = conectar();
         PreparedStatement statement =
             connection.prepareStatement(sql)) {

        statement.setLong(1, tarefa.getTaskInstanceId());

        try (ResultSet resultSet = statement.executeQuery()) {
            while (resultSet.next()) {
                Set<String> validos = new LinkedHashSet<>();
                adicionarEmail(
                    validos,
                    resultSet.getString("email")
                );

                for (String email : validos) {
                    porEmail.putIfAbsent(
                        email,
                        new DestinatarioNotificacao(
                            resultSet.getString("fullname"),
                            email
                        )
                    );
                }
            }
        }
    }

    return new ArrayList<>(porEmail.values());
}

    public List<String> obterDestinatarios(
            TarefaNotificacao tarefa) throws Exception {

        Set<String> emails = new LinkedHashSet<>();

        adicionarEmail(
            emails,
            tarefa.getEmail()
        );

        if (emails.isEmpty()) {
            emails.addAll(
                buscarEmailsDaPool(
                    tarefa.getTaskInstanceId()
                )
            );
        }

        return new ArrayList<>(emails);
    }

    private void adicionarEmail(
            Set<String> emails,
            String email) {

        if (email == null || email.trim().isEmpty()) {
            return;
        }

        String valor = email.trim();

        int inicioMailto = valor.indexOf("mailto:");

        if (inicioMailto >= 0) {
            int inicio = inicioMailto + "mailto:".length();
            int fim = valor.indexOf(")", inicio);

            valor = fim >= 0
                ? valor.substring(inicio, fim)
                : valor.substring(inicio);
        } else if (valor.startsWith("[")
                && valor.contains("](")) {

            int fimTexto = valor.indexOf("](");

            valor = valor.substring(1, fimTexto);
        }

        valor = valor
            .replace("<", "")
            .replace(">", "")
            .trim()
            .toLowerCase();

        if (valor.matches(
                "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            emails.add(valor);
        }
    }

    private Long obterLong(
            ResultSet resultSet,
            String coluna) throws Exception {

        long valor = resultSet.getLong(coluna);

        if (resultSet.wasNull()) {
            return null;
        }

        return valor;
    }

    private Integer obterInteger(
            ResultSet resultSet,
            String coluna) throws Exception {

        int valor = resultSet.getInt(coluna);

        if (resultSet.wasNull()) {
            return null;
        }

        return valor;
    }
}
