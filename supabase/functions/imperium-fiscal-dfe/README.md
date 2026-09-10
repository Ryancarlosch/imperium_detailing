# imperium-fiscal-dfe — Fiscal V33

Edge Function autenticada para obter XML completo de NF-e modelo 55 recebida.

## Segurança
- deploy com `verify_jwt = true`;
- valida o JWT novamente com `auth.getUser()`;
- token Focus NFe fica somente em `FOCUS_NFE_TOKEN` no Supabase;
- `FOCUS_NFE_CNPJ`, quando usado, é lido somente do servidor e não pode ser sobrescrito pelo APK;
- nenhuma manifestação do destinatário é executada automaticamente.

## Status
`POST {"acao":"status"}` devolve somente flags de configuração, nunca segredos.

## Segredos esperados
- `FISCAL_DFE_PROVIDER=focusnfe` (opcional; padrão focusnfe)
- `FOCUS_NFE_TOKEN=<token>` (necessário para consulta automática de NF-e 55)
- `FOCUS_NFE_CNPJ=<CNPJ destinatário>` (recomendado quando a conta possui múltiplos CNPJs)

Sem token, a importação manual por XML continua funcionando normalmente.
