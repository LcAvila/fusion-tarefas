package br.com.fusion.tarefas.model;

import java.util.ArrayList;
import java.util.List;

public class ResultadoEnvioNotificacao {

    private int aceitas;
    private final List<String> falhas = new ArrayList<>();

    public void registrarAceita() {
        aceitas++;
    }

    public void registrarFalha(String falha) {
        falhas.add(falha);
    }

    public int getAceitas() {
        return aceitas;
    }

    public List<String> getFalhas() {
        return falhas;
    }
}
