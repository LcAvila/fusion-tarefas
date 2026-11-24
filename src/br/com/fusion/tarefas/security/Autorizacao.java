package br.com.fusion.tarefas.security;

import java.lang.reflect.Method;
import java.security.Principal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import br.com.fusion.tarefas.config.AppConfig;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;

/**
 * Identificação e autorização de usuários do Fusion.
 *
 * A identificação usa a API padrão de Servlet (principal/remote user) e, como
 * alternativa, atributos de sessão comumente populados pelo Fusion. A
 * autorização exige que o usuário pertença ao grupo administrativo configurado
 * em {@link #GRUPO_ADMIN}, consultando as tabelas do Fusion via JDBC.
 *
 * Observação: a única API pública utilizada é a Servlet API padrão e o banco de
 * dados do Fusion. Nenhuma API interna proprietária é presumida.
 */
public final class Autorizacao {

    /** Código do grupo administrativo exigido para consultar e notificar tarefas. */
    public static final String GRUPO_ADMIN = "admG";

    private Autorizacao() {
    }

    /**
     * Retorna o identificador do usuário autenticado, ou {@code null} quando
     * não for possível determiná-lo.
     */
    public static String identificarUsuario(
            HttpServletRequest request,
            HttpSession session) {

        if (request == null) {
            return null;
        }

        Principal principal = request.getUserPrincipal();

        if (principal != null && principal.getName() != null
                && !principal.getName().trim().isEmpty()) {
            return principal.getName().trim();
        }

        String remoto = request.getRemoteUser();

        if (remoto != null && !remoto.trim().isEmpty()) {
            return remoto.trim();
        }

        if (session != null) {
            String[] atributos = {
                "user", "usuario", "currentUser", "loggedUser",
                "authenticatedUser", "fusionUser", "neoUser"
            };

            for (String atributo : atributos) {
                String identificador =
                    extrairIdentificador(session.getAttribute(atributo));

                if (identificador != null && !identificador.isEmpty()) {
                    return identificador;
                }
            }
        }

        return null;
    }

    /**
     * Verifica se o identificador informado pertence ao grupo administrativo
     * exigido, consultando o banco configurado.
     */
    public static boolean ehAdministrador(
            AppConfig config,
            String identificador) throws Exception {

        if (config == null) {
            throw new IllegalArgumentException("Configuração obrigatória.");
        }

        if (identificador == null || identificador.trim().isEmpty()) {
            return false;
        }

        String valor = identificador.trim();

        String sqlNeoId =
            "SELECT COUNT(*) AS autorizado FROM neouser U "
          + "INNER JOIN securityentity UsuarioSE "
          + "ON UsuarioSE.neoId = U.neoId "
          + "INNER JOIN securityentity GrupoSE "
          + "ON GrupoSE.neoId = U.group_neoId "
          + "WHERE UsuarioSE.neoId = ? "
          + "AND GrupoSE.code = ? AND GrupoSE.active = 1";

        String sqlCodigo =
            "SELECT COUNT(*) AS autorizado FROM neouser U "
          + "INNER JOIN securityentity UsuarioSE "
          + "ON UsuarioSE.neoId = U.neoId "
          + "INNER JOIN securityentity GrupoSE "
          + "ON GrupoSE.neoId = U.group_neoId "
          + "WHERE UsuarioSE.code = ? "
          + "AND GrupoSE.code = ? AND GrupoSE.active = 1";

        Class.forName("com.mysql.cj.jdbc.Driver");

        try (Connection connection = DriverManager.getConnection(
                config.required("db.url"),
                config.required("db.user"),
                config.required("db.password"))) {

            if (valor.matches("\\d+")) {
                try (PreparedStatement statement =
                        connection.prepareStatement(sqlNeoId)) {

                    statement.setLong(1, Long.parseLong(valor));
                    statement.setString(2, GRUPO_ADMIN);

                    try (ResultSet resultSet = statement.executeQuery()) {
                        if (resultSet.next()
                                && resultSet.getInt("autorizado") > 0) {
                            return true;
                        }
                    }
                }
            }

            try (PreparedStatement statement =
                    connection.prepareStatement(sqlCodigo)) {

                statement.setString(1, valor);
                statement.setString(2, GRUPO_ADMIN);

                try (ResultSet resultSet = statement.executeQuery()) {
                    return resultSet.next()
                        && resultSet.getInt("autorizado") > 0;
                }
            }
        }
    }

    private static String extrairIdentificador(Object usuario) {
        if (usuario == null) {
            return null;
        }

        if (usuario instanceof String || usuario instanceof Number) {
            return String.valueOf(usuario).trim();
        }

        String[] metodos = {
            "getCode", "getNeoId", "getUserName", "getUsername", "getLogin"
        };

        for (String nomeMetodo : metodos) {
            try {
                Method metodo = usuario.getClass().getMethod(nomeMetodo);
                Object valor = metodo.invoke(usuario);

                if (valor != null && !String.valueOf(valor).trim().isEmpty()) {
                    return String.valueOf(valor).trim();
                }
            } catch (Exception ignorado) {
                // Tenta o próximo identificador.
            }
        }

        return null;
    }
}
