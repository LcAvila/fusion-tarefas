package br.com.fusion.tarefas.config;

import java.sql.Connection;
import java.sql.DriverManager;

/**
 * Suporte a múltiplos bancos de dados (MySQL e PostgreSQL).
 *
 * O tipo é determinado pela propriedade opcional {@code db.type} ou, quando ela
 * não existir, deduzido do prefixo de {@code db.url} ({@code jdbc:mysql:} ou
 * {@code jdbc:postgresql:}). A dedução preserva a compatibilidade com os
 * arquivos de propriedades de instalações anteriores, que informavam apenas
 * {@code db.url}.
 *
 * Os trechos de SQL específicos de cada banco ficam centralizados aqui, para que
 * as consultas permaneçam parametrizadas e idênticas em comportamento lógico.
 */
public final class BancoDados {

    public static final String MYSQL = "mysql";
    public static final String POSTGRESQL = "postgresql";

    private BancoDados() {
    }

    /** Identifica o tipo de banco configurado ({@code mysql} ou {@code postgresql}). */
    public static String tipo(AppConfig config) {
        String informado = config.optional("db.type", "").toLowerCase();

        if (!informado.isEmpty()) {
            if (informado.equals(MYSQL)) {
                return MYSQL;
            }
            if (informado.equals("postgres") || informado.equals(POSTGRESQL)) {
                return POSTGRESQL;
            }
            throw new IllegalStateException(
                "Valor inválido em db.type: " + informado
                    + " (use mysql ou postgresql)."
            );
        }

        String url = config.required("db.url").toLowerCase();

        if (url.startsWith("jdbc:postgresql:")) {
            return POSTGRESQL;
        }
        if (url.startsWith("jdbc:mysql:")) {
            return MYSQL;
        }

        throw new IllegalStateException(
            "Não foi possível identificar o banco em db.url. "
                + "Defina db.type=mysql ou db.type=postgresql."
        );
    }

    /** Classe do driver JDBC correspondente ao tipo informado. */
    public static String driver(String tipo) {
        return POSTGRESQL.equals(tipo)
            ? "org.postgresql.Driver"
            : "com.mysql.cj.jdbc.Driver";
    }

    /** Nome legível do banco, usado em mensagens de erro. */
    public static String nome(String tipo) {
        return POSTGRESQL.equals(tipo) ? "PostgreSQL" : "MySQL";
    }

    /**
     * Abre uma conexão usando a configuração informada, carregando o driver
     * correspondente ao banco. A aplicação usa apenas leitura nas tabelas do
     * Fusion (SELECT); nenhuma alteração de estrutura ou de dados é feita.
     */
    public static Connection conectar(AppConfig config) throws Exception {
        String tipo = tipo(config);

        try {
            Class.forName(driver(tipo));
        } catch (ClassNotFoundException e) {
            throw new IllegalStateException(
                "Driver JDBC do " + nome(tipo)
                    + " não encontrado no classpath (WEB-INF/lib).",
                e
            );
        }

        return DriverManager.getConnection(
            config.required("db.url"),
            config.required("db.user"),
            config.required("db.password")
        );
    }

    /**
     * Expressão que retorna o número de dias completos entre a coluna de prazo e
     * o instante atual, reproduzindo {@code TIMESTAMPDIFF(DAY, coluna, NOW())}.
     *
     * MySQL: {@code TIMESTAMPDIFF(DAY, coluna, NOW())}.
     * PostgreSQL: segundos decorridos divididos por 86400, truncados em direção
     * a zero — mesmo comportamento do {@code TIMESTAMPDIFF} para prazos já
     * vencidos (o filtro garante {@code coluna < NOW()}).
     */
    public static String diasAtraso(String tipo, String coluna) {
        if (POSTGRESQL.equals(tipo)) {
            return "TRUNC(EXTRACT(EPOCH FROM (NOW() - " + coluna
                + ")) / 86400)";
        }
        return "TIMESTAMPDIFF(DAY, " + coluna + ", NOW())";
    }

    /**
     * Expressão "data + 1 dia" aplicada a um parâmetro ligado ({@code ?}),
     * reproduzindo {@code DATE_ADD(?, INTERVAL 1 DAY)}.
     *
     * MySQL: {@code DATE_ADD(?, INTERVAL 1 DAY)}.
     * PostgreSQL: {@code (CAST(? AS DATE) + INTERVAL '1 day')}.
     */
    public static String maisUmDia(String tipo, String parametro) {
        if (POSTGRESQL.equals(tipo)) {
            return "(CAST(" + parametro + " AS DATE) + INTERVAL '1 day')";
        }
        return "DATE_ADD(" + parametro + ", INTERVAL 1 DAY)";
    }

    /**
     * Predicado para coluna de indicador ativo. No MySQL a coluna é numérica
     * ({@code = 1}); no PostgreSQL é tratada como booleana ({@code = TRUE}).
     */
    public static String ativo(String tipo, String coluna) {
        return POSTGRESQL.equals(tipo)
            ? coluna + " = TRUE"
            : coluna + " = 1";
    }
}
