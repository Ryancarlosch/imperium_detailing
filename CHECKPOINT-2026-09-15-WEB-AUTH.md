# Checkpoint Imperium — Web/Auth e onboarding comercial

Data: 2026-09-15
Branch de desenvolvimento: `desenvolvimento`

## Arquitetura definida

- A empresa/administrador entra com **e-mail e senha**.
- O mesmo login funciona no **Web e no aplicativo Mobile** usando Supabase Auth.
- A conta autenticada representa o acesso administrativo da empresa.
- Funcionários ficam **dentro da empresa do administrador**; não são tratados como empresas/assinaturas SaaS independentes.
- O cadastro e gerenciamento dos funcionários acontece dentro do Imperium da própria empresa.

## Fluxo comercial concluído

A etapa implementada é:

1. A venda/licença é registrada no painel comercial existente do Imperium.
2. O backend cria a empresa, a licença e um convite pendente para o e-mail informado na assinatura.
3. O cliente abre o Imperium no Web ou Mobile usando exatamente esse e-mail.
4. No primeiro acesso, cria e confirma uma senha com pelo menos 8 caracteres.
5. Quando a confirmação de e-mail do Supabase estiver habilitada, o cliente confirma o endereço recebido por e-mail.
6. No primeiro login autenticado, `imperium_resgatar_convite()` procura a assinatura pendente pelo e-mail autenticado.
7. A RPC vincula automaticamente o usuário à empresa como administrador/proprietário, marca o convite como aceito e o onboarding como ativo.
8. A licença existente da empresa continua sendo a fonte de verdade para liberação de acesso.
9. Nos próximos logins o mesmo vínculo é reutilizado de forma idempotente.
10. O mesmo e-mail e senha passam a funcionar tanto no Web quanto no aplicativo.

Não foi criada integração fictícia com Stripe ou outro gateway. Nesta etapa, “assinatura” significa a licença/venda registrada pelo painel comercial já existente. Checkout/cobrança externa deverá ser uma etapa separada somente quando o meio de pagamento for definido.

## Supabase aplicado

Migration aplicada em produção e salva no repositório:

`supabase/migrations/20260915201403_onboarding_comercial_email_senha_v1.sql`

Principais regras de `imperium_resgatar_convite()`:

- exige sessão autenticada;
- usa o e-mail do próprio usuário autenticado;
- aceita somente vínculo administrativo (`admin` ou `proprietario`);
- convite pendente do e-mail tem prioridade, permitindo inclusive ativar uma segunda empresa;
- faz `upsert` em `empresa_usuarios`;
- registra `owner_id`, `aceito_por`, `aceito_em` e onboarding ativo;
- se a assinatura já tiver sido ativada, reutiliza o vínculo existente;
- se não houver assinatura/vínculo para aquele e-mail, retorna erro claro;
- `SECURITY DEFINER` com `search_path` vazio e objetos totalmente qualificados;
- execução de `imperium_resgatar_convite()` removida de `anon/public` e concedida apenas a `authenticated`.

Também foram restringidas a usuários autenticados as RPCs comerciais `imperium_admin_criar_cliente` e `imperium_admin_criar_empresa_beta`; elas continuam fazendo a validação interna de administrador comercial.

## Mobile

`lib/screens/empresa_primeiro_acesso_page.dart` agora apresenta o fluxo como **Ativar assinatura**:

- `E-mail da assinatura`;
- criar senha;
- confirmar senha;
- `Criar senha e ativar assinatura`;
- opção `Já tenho senha • ativar minha assinatura`;
- orientação de confirmação de e-mail quando necessário;
- vínculo automático via `CloudSessionService.prepararSessao()`.

`lib/services/cloud_session_service.dart` chama `imperium_resgatar_convite()` antes de listar as empresas vinculadas e propaga um erro útil quando o e-mail autenticado não corresponde a uma assinatura pendente.

## Web

`lib/main_web.dart` já utiliza o mesmo Supabase Auth por e-mail/senha e, após autenticar, chama `imperium_resgatar_convite()` antes de carregar as empresas vinculadas. A nova RPC do Supabase faz com que o Web use o mesmo onboarding automático do Mobile sem criar um sistema paralelo.

## Testes adicionados/ajustados

- `test/onboarding_comercial_email_senha_source_test.dart`
- `test/login_email_senha_source_test.dart`

Eles protegem:

- segurança/idempotência da migration;
- primeiro acesso por e-mail e senha;
- ativação automática no Mobile;
- reutilização da mesma RPC no Web;
- ausência de regressão para Magic Link/PIN como login principal da empresa.

## Commits desta etapa

- `63ab3e0e...` — `feat(onboarding): automatiza vinculo da assinatura por email`
- `2abbae34...` — `feat(onboarding): propaga erro de ativacao da assinatura`
- `6f63970a...` — `ui(onboarding): conclui ativacao comercial por email e senha`
- `945745ae...` — `test(onboarding): protege fluxo comercial por email e senha`
- `0ffd239e...` — `test(auth): alinha primeiro acesso com ativacao da assinatura`
- `db2d2abc...` — `style: aplica dart format`

## Validação final desta etapa

O commit de autoformatação `db2d2abc...` corrigiu a única causa observada nas execuções anteriores de `Flutter Quality` e `Web Preview Build`: o passo `Check formatting`.

Este checkpoint cria um novo push humano somente para disparar novamente os workflows sobre o código já formatado. Antes de considerar a etapa encerrada, confirmar:

1. `Flutter Quality` verde;
2. `Web Preview Build` verde;
3. branch `vercel-web` atualizada com o build do commit final;
4. migration `onboarding_comercial_email_senha_v1` presente no Supabase de produção.

## Limite de escopo

A próxima tarefa não deve alterar este fluxo comercial sem necessidade. Integração com checkout/gateway de pagamento, planos públicos ou cobrança recorrente automática é uma etapa posterior e separada.
