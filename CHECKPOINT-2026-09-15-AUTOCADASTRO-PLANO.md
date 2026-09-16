# Checkpoint Imperium — Autocadastro + Plano

Data local do checkpoint: 2026-09-15
Branch principal de desenvolvimento: `desenvolvimento`
HEAD antes deste checkpoint: `72067d0336b20429337657b7467bd88f9d206ca9`

## Estado funcional concluído

O fluxo novo de acesso da empresa foi simplificado para cadastro livre, sem autorização manual prévia do administrador comercial.

Fluxo esperado:

1. Cliente toca em **Criar conta grátis**.
2. Informa e-mail e senha.
3. Confirma o e-mail.
4. O sistema cria/vincula automaticamente a empresa.
5. A empresa recebe **30 dias grátis** de teste.
6. A mesma conta funciona no Web e no Mobile.
7. A empresa aparece automaticamente no painel comercial do Imperium.
8. O administrador comercial pode acompanhar, adicionar dias, bloquear e reativar manualmente.
9. Ao vencer a licença, o acesso ao sistema é bloqueado.
10. Mesmo bloqueado, o cliente deve continuar conseguindo acessar **Plano / renovar acesso**.
11. A tela **Plano e assinatura** já foi criada e ficou preparada para futura integração da InfinitePay.
12. O fluxo legado de Magic Link deixou de ser o caminho principal da empresa.

## Backend / Supabase

- Autocadastro de empresa implementado via RPC idempotente.
- Criação automática de vínculo proprietário/admin.
- Teste gratuito de 30 dias criado automaticamente.
- Confirmação de e-mail é requisito para criação/liberação da empresa.
- Proteção contra duplicidade quando Web e Mobile tentam preparar o primeiro acesso ao mesmo tempo.
- A licença continua sendo a fonte de verdade para liberar/bloquear o acesso.
- Painel comercial continua enxergando empresas criadas automaticamente.

## Validação já concluída

- Código funcional de autocadastro/Plano/licença conferido.
- Testes específicos de cadastro/Plano/licença coerentes com a implementação.
- `dart format` passou.
- `flutter analyze` passou.
- O backend foi exercitado em transação com uma conta real: criou empresa de teste com plano **Teste 30 dias** e validade de 30 dias; a transação foi revertida para não deixar dados de teste no banco.

## Ponto exato para retomar

Ainda falta somente fechar a validação final:

1. localizar o nome exato do **teste legado** que ainda derruba o `Flutter Quality`;
2. corrigir apenas essa expectativa antiga, sem alterar o autocadastro, os 30 dias grátis, o bloqueio por licença ou a tela Plano;
3. confirmar `Flutter Quality` totalmente verde;
4. confirmar `Web Preview Build`;
5. confirmar publicação da nova `vercel-web`;
6. promover a versão correta no Vercel, se ela aparecer como Preview;
7. testar o fluxo completo em produção Web e depois no Mobile.

## Próximo desenvolvimento após validação

Depois que o fluxo estiver validado em produção, integrar **InfinitePay** dentro da área **Plano**, para permitir antecipação/renovação do plano e atualização automática da licença após pagamento aprovado.

## Regra importante

Não voltar ao modelo de convite/autorização manual para novas empresas. O modelo atual é autocadastro livre com 30 dias grátis e controle administrativo posterior pelo painel comercial.
