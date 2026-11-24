package br.com.fusion.tarefas.model;

public class DestinatarioNotificacao {

    private final String nome;
    private final String email;

    public DestinatarioNotificacao(String nome, String email) {
        this.nome = nome;
        this.email = email;
    }

    public String getNome() {
        return nome;
    }

    public String getEmail() {
        return email;
    }
}
