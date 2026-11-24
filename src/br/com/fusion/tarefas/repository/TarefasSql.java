package br.com.fusion.tarefas.repository;

import java.sql.PreparedStatement;
import java.util.ArrayList;
import java.util.List;

import br.com.fusion.tarefas.config.BancoDados;

/**
 * Monta as consultas parametrizadas da tela de tarefas atrasadas.
 *
 * A montagem fica centralizada aqui para ser reaproveitada pela JSP, pelo
 * repositório e pela validação executada pelo instalador, e para que as
 * diferenças entre MySQL e PostgreSQL (funções de data e de valor nulo) fiquem
 * isoladas em {@link BancoDados}.
 */
public final class TarefasSql {

    /** Consulta pronta: texto SQL e parâmetros a vincular, na ordem. */
    public static final class Consulta {
        private final String sql;
        private final List<Object> parametros;

        Consulta(String sql, List<Object> parametros) {
            this.sql = sql;
            this.parametros = parametros;
        }

        public String getSql() {
            return sql;
        }

        public List<Object> getParametros() {
            return parametros;
        }
    }

    private TarefasSql() {
    }

    /** Trecho comum de junções e filtros fixos, independente do banco. */
    public static String base() {
        return "FROM wfprocess WFP "
            + "INNER JOIN processmodel PM ON PM.neoId = WFP.model_neoId "
            + "INNER JOIN taskinstance TI ON TI.processId = WFP.neoId "
            + "LEFT JOIN neouser U_REQ ON U_REQ.neoId = WFP.requester_neoId "
            + "LEFT JOIN neouser U_ATUAL ON U_ATUAL.neoId = TI.owner_neoId "
            + "WHERE WFP.processState = 0 "
            + "AND TI.status IN (0,1,2,3) "
            + "AND TI.dueDate IS NOT NULL "
            + "AND TI.dueDate < NOW() ";
    }

    public static Consulta contar(
            String tipo,
            String solicitante, String processo, String nomeTarefa,
            String dataInicio, String dataFim,
            Integer atrasoMin, Integer atrasoMax) {

        StringBuilder sql = new StringBuilder("SELECT COUNT(*) AS total ");
        sql.append(base());

        List<Object> parametros = new ArrayList<>();
        adicionarFiltros(sql, parametros, tipo, solicitante, processo,
            nomeTarefa, dataInicio, dataFim, atrasoMin, atrasoMax);

        return new Consulta(sql.toString(), parametros);
    }

    public static Consulta listar(
            String tipo,
            String solicitante, String processo, String nomeTarefa,
            String dataInicio, String dataFim,
            Integer atrasoMin, Integer atrasoMax,
            int limite, int offset) {

        StringBuilder sql = new StringBuilder(
            "SELECT "
          + "WFP.neoId AS process_id, "
          + "TI.id AS task_instance_id, "
          + "TI.task_neoId AS task_id, "
          + "TI.activity_neoId AS activity_id, "
          + "PM.title AS processo, "
          + "WFP.code AS protocolo, "
          + "U_REQ.fullname AS solicitante, "
          + "COALESCE(U_ATUAL.fullname, 'Tarefa não atribuída') AS responsavel, "
          + "U_ATUAL.neoId AS responsavel_neoId, "
          + "U_ATUAL.email AS email_responsavel, "
          + "WFP.startDate AS data_solicitacao, "
          + "TI.taskName AS tarefa, "
          + "TI.dueDate AS data_vencimento, "
          + BancoDados.diasAtraso(tipo, "TI.dueDate") + " AS dias_atraso, "
          + "WFP.entityTitle AS descricao "
        );
        sql.append(base());

        List<Object> parametros = new ArrayList<>();
        adicionarFiltros(sql, parametros, tipo, solicitante, processo,
            nomeTarefa, dataInicio, dataFim, atrasoMin, atrasoMax);

        sql.append("ORDER BY TI.dueDate ASC LIMIT ? OFFSET ?");
        parametros.add(limite);
        parametros.add(offset);

        return new Consulta(sql.toString(), parametros);
    }

    public static Consulta valoresDistintos(String tipo, String coluna) {
        String sql = "SELECT DISTINCT " + coluna + " AS valor "
            + base()
            + "AND " + coluna + " IS NOT NULL AND " + coluna + " <> ''";

        return new Consulta(sql, new ArrayList<>());
    }

    private static void adicionarFiltros(
            StringBuilder sql,
            List<Object> parametros,
            String tipo,
            String solicitante,
            String processo,
            String nomeTarefa,
            String dataInicio,
            String dataFim,
            Integer atrasoMin,
            Integer atrasoMax) {

        if (solicitante != null && !solicitante.trim().isEmpty()) {
            sql.append("AND U_REQ.fullname LIKE ? ");
            parametros.add("%" + solicitante.trim() + "%");
        }

        if (processo != null && !processo.trim().isEmpty()) {
            sql.append("AND PM.title LIKE ? ");
            parametros.add("%" + processo.trim() + "%");
        }

        if (nomeTarefa != null && !nomeTarefa.trim().isEmpty()) {
            sql.append("AND TI.taskName LIKE ? ");
            parametros.add("%" + nomeTarefa.trim() + "%");
        }

        if (dataInicio != null && !dataInicio.trim().isEmpty()) {
            sql.append("AND WFP.startDate >= ? ");
            parametros.add(java.sql.Date.valueOf(dataInicio));
        }

        if (dataFim != null && !dataFim.trim().isEmpty()) {
            sql.append("AND WFP.startDate < ")
                .append(BancoDados.maisUmDia(tipo, "?"))
                .append(" ");
            parametros.add(java.sql.Date.valueOf(dataFim));
        }

        if (atrasoMin != null) {
            sql.append("AND ")
                .append(BancoDados.diasAtraso(tipo, "TI.dueDate"))
                .append(" >= ? ");
            parametros.add(atrasoMin);
        }

        if (atrasoMax != null) {
            sql.append("AND ")
                .append(BancoDados.diasAtraso(tipo, "TI.dueDate"))
                .append(" <= ? ");
            parametros.add(atrasoMax);
        }
    }

    /** Vincula os parâmetros na ordem em que foram adicionados. */
    public static void aplicar(
            PreparedStatement statement,
            List<Object> parametros) throws Exception {

        for (int i = 0; i < parametros.size(); i++) {
            Object parametro = parametros.get(i);

            if (parametro instanceof java.sql.Date) {
                statement.setDate(i + 1, (java.sql.Date) parametro);
            } else if (parametro instanceof Integer) {
                statement.setInt(i + 1, (Integer) parametro);
            } else if (parametro instanceof Long) {
                statement.setLong(i + 1, (Long) parametro);
            } else {
                statement.setString(
                    i + 1,
                    parametro == null ? null : parametro.toString()
                );
            }
        }
    }
}
