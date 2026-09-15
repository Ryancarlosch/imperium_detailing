# Checkpoint Imperium — Web/Auth

Data: 2026-09-15
Branch de desenvolvimento: `desenvolvimento`
Commit de referência antes deste checkpoint: `986f2f9ab422285f47083b86350e4cea985b7636`

## Onde paramos

Estamos trabalhando no fluxo de autenticação Web + Mobile do Imperium, preparando o sistema para ser vendido para outras empresas.

### Decisão principal de arquitetura

- A empresa/administrador entra com **e-mail e senha**.
- O mesmo login deve funcionar no **Web e no aplicativo Mobile**.
- A conta autenticada representa o acesso da empresa.
- Funcionários ficam **dentro da empresa do administrador**; não são tratados como empresas/assinaturas SaaS independentes.
- O cadastro e gerenciamento dos funcionários acontece dentro do Imperium da própria empresa.

## O que já foi implementado

### Login da empresa

- Tela de login por e-mail e senha criada/ajustada.
- Campo passou a indicar `E-mail da empresa`.
- Botão principal passou a indicar `Entrar na empresa`.
- Primeiro acesso direcionado para criação/ativação da empresa.
- Recuperação de senha mantida.
- Seleção de empresa mantida quando um mesmo usuário administrador possui mais de uma empresa vinculada.

### Sessão cloud

- `CloudSessionService` restringido para acesso de empresa por papéis de administrador/proprietário.
- Login cloud de funcionário não cria uma empresa separada.
- Funcionário permanece como registro interno pertencente ao tenant/empresa.

### Primeiro acesso

- Fluxo passou de Magic Link/PIN local para e-mail + senha usando Supabase Auth.
- Preparado para permitir que a empresa use as mesmas credenciais na Web e no Mobile.

### Funcionários / ponto

Últimos commits antes deste checkpoint:

- `a8ba1de6...` — `refactor(ponto): remove vinculo manual Supabase de funcionarios`
- `8520cd4c...` — `refactor(ponto): ativa fluxo interno de funcionarios`
- `986f2f9a...` — `test(ponto): protege funcionario interno sem Supabase manual`

Esses ajustes reforçam que funcionário é interno à empresa e não precisa de vínculo manual separado no Supabase para funcionar como empresa SaaS.

## Supabase

Na auditoria atual não foi identificada migration/SQL obrigatória pendente para o login já implementado.

A estrutura existente de vínculo de usuário/empresa e o fluxo `imperium_resgatar_convite` já dão base para associar o usuário autenticado à empresa.

Não aplicar migration nova apenas para repetir o fluxo atual sem antes revisar o onboarding comercial.

## Vercel / Web

- O desenvolvimento continua na branch `desenvolvimento`.
- A branch `vercel-web` é gerada pelo workflow de build/deploy Web.
- Não desenvolver diretamente em `vercel-web`.
- Antes de continuar, conferir GitHub Actions e confirmar que o último commit funcional de `desenvolvimento` chegou ao `vercel-web`.

## Próximo passo principal

Construir o onboarding comercial self-service:

1. Cliente assina um plano.
2. Informa o e-mail da empresa.
3. Cria/confirma a senha.
4. O sistema cria ou identifica a empresa/tenant.
5. Vincula automaticamente o usuário autenticado como administrador/proprietário.
6. Ativa a licença/plano correspondente.
7. O cliente entra no Imperium imediatamente com o mesmo e-mail e senha no Web ou Mobile.

## Antes de implementar o próximo passo

Revisar os componentes já existentes de:

- empresa/tenant cloud;
- convite/vínculo de empresa;
- licença/plano;
- RPCs do Supabase;
- fluxo de primeiro acesso;
- eventual integração de cobrança/assinatura.

Objetivo: reaproveitar o que já existe e evitar criar dois sistemas paralelos de onboarding/licenciamento.

## Regra para retomada

Ao retomar o desenvolvimento:

1. Abrir este checkpoint.
2. Confirmar HEAD atual de `desenvolvimento`.
3. Conferir Actions (`Flutter Quality` e `Web Preview Build`).
4. Conferir se `vercel-web` está sincronizada com o último código funcional.
5. Continuar pelo onboarding comercial/assinatura automática da empresa.
