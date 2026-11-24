# Política de segurança

## Escopo

Este projeto é uma extensão da Fusion Platform. Ele não substitui os controles
de segurança da plataforma hospedeira. A responsabilidade por autenticação de
sessão, transporte (TLS) e proteção de infraestrutura permanece com o ambiente
do Fusion.

## Como relatar uma vulnerabilidade

Não abra issues públicas para relatar vulnerabilidades. Envie um relato privado
ao mantenedor do repositório contendo:

- Descrição do problema e impacto potencial.
- Passos para reproduzir.
- Versão do Fusion/Tomcat/Java utilizada.
- Qualquer evidência (logs sem dados sensíveis, capturas, requisições).

Não inclua credenciais, dados pessoais ou informações de clientes no relato.

## Modelo de ameaças considerado

- **Autenticação:** o endpoint de notificação e a tela de tarefas exigem usuário
  autenticado no Fusion.
- **Autorização:** o acesso é restrito ao grupo administrativo configurado
  (`admG`) por consulta ao banco do Fusion.
- **CSRF:** o POST de notificação exige cabeçalho `X-Requested-With` e valida a
  origem quando os cabeçalhos `Origin`/`Referer` estão presentes.
- **Validação de entrada:** o identificador de tarefa recebido é validado antes
  do uso.
- **Exposição de erros:** mensagens devolvidas ao cliente são genéricas; os
  detalhes são registrados apenas no log do servidor.

## Limitações conhecidas

- A aplicação não inicia o servlet se a propriedade de sistema
  `fusion.config.path` não estiver definida.
- O envio de e-mail utiliza STARTTLS com autenticação; outros mecanismos, como
  OAuth2, não foram implementados nem validados.
- A conta de banco utilizada deve ser restrita a leitura nas tabelas
  consultadas.
- A verificação de autorização depende da estrutura de grupos do Fusion
  (`securityentity`/`neouser`). Caso o modelo de grupos do ambiente seja
  diferente, a verificação precisa ser adaptada e revalidada.
- **Autorização por tarefa não implementada.** A autorização atual é por grupo
  administrativo: um usuário autorizado pode notificar qualquer tarefa
  consultada. Não há verificação de que o usuário seja o responsável, o
  solicitante ou tenha vínculo com a tarefa específica. Implementar essa
  restrição exigiria consultas adicionais ao modelo de permissões do Fusion que
  não foram validadas neste projeto. Enquanto isso não for demonstrado no
  ambiente alvo, o recurso **não deve ser considerado pronto para produção**.
- A instalação automatizada exige systemd e um contexto Tomcat expandido.

## Boas práticas para implantação

- Mantenha o arquivo de propriedades fora do diretório web, com permissão `600`
  e proprietário do processo do Fusion.
- Nunca versione credenciais de banco de dados ou SMTP.
- Restrinja o endpoint de notificação a usuários autorizados e valide o fluxo em
  um ambiente de teste antes de usar em produção.
- Mantenha Java, Tomcat e as bibliotecas (MySQL Connector/J, Jakarta Mail,
  Angus Mail) atualizadas conforme as recomendações dos respectivos projetos.
