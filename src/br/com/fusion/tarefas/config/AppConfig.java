package br.com.fusion.tarefas.config;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

public final class AppConfig {
	private final Properties properties;

	public AppConfig(Path arquivo) throws IOException {
		properties = new Properties();
		try (InputStream input = Files.newInputStream(arquivo)) {
			properties.load(input);
		}
	}

	public String required(String chave) {
		String valor = properties.getProperty(chave);
		if (valor == null || valor.isBlank()) {
			throw new IllegalStateException("Configuração ausente: " + chave);
		}
		return valor.trim();
	}

	public String optional(String chave, String padrao) {
		String valor = properties.getProperty(chave);
		return valor == null || valor.isBlank() ? padrao : valor.trim();
	}
}
