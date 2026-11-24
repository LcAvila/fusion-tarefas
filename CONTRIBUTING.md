# Contribuindo

Obrigado pelo interesse em contribuir com o Fusion Tarefas.

## Pré-requisitos

- JDK 21 com `javac`.
- Git.
- Um ambiente Fusion de teste para validar alterações que dependam do banco de
  dados ou do contêiner de servlets.

## Fluxo de contribuição

1. Faça um fork do repositório e crie uma branch descritiva
   (por exemplo, `feature/filtro-por-responsavel`).
2. Faça alterações pequenas e focadas.
3. Compile localmente antes de enviar:

   ```bash
   javac -proc:none -encoding UTF-8 \
     -cp "caminho/para/servlet-api.jar" \
     -sourcepath src -d /tmp/build \
     $(find src -name '*.java')
   ```

4. Verifique a sintaxe dos scripts alterados:

   ```bash
   bash -n install-fusion-tarefas.sh
   bash -n scripts/build-release.sh
   ```

5. Abra um pull request descrevendo o problema e a solução, incluindo os
   comandos usados para validar a mudança.

## Padrões de código

- Mantenha o estilo existente (indentação, nomes e organização de pacotes).
- Não introduza credenciais, domínios, IPs ou caminhos específicos de um
  ambiente.
- Toda nova configuração deve ter uma chave documentada em
  `config/fusion-tarefas.properties.example`.
- Preserve o comportamento atual da JSP, dos filtros, das consultas e do envio
  de notificações, salvo quando a mudança for o objetivo da contribuição.

## Segurança

- Não inclua dados reais de pessoas, credenciais ou informações de clientes em
  commits, testes ou capturas de tela.
- Alterações em autenticação, autorização, validação de entrada ou no endpoint
  de notificações devem descrever claramente o impacto de segurança.
- Relate vulnerabilidades conforme descrito em [SECURITY.md](SECURITY.md), e não
  por meio de issues públicas.

## Licença

Ao contribuir, você concorda em licenciar sua contribuição sob os termos da
licença do projeto ([LICENSE](LICENSE)).
