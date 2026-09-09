# imperium-fiscal-dfe

Edge Function autenticada para obter XML completo de NF-e modelo 55 recebida pela empresa.

## Segurança

- `verify_jwt = true` no deploy.
- O token do provedor fiscal nunca deve entrar no APK ou no Git.
- A função já está implantada no projeto Supabase Imperium Manager.

## Segredos esperados

- `FISCAL_DFE_PROVIDER=focusnfe` (opcional; `focusnfe` é o padrão)
- `FOCUS_NFE_TOKEN=<token da conta Focus NFe>` (obrigatório para ativar NF-e 55)
- `FOCUS_NFE_CNPJ=<CNPJ da empresa>` (opcional, útil quando a conta possui múltiplas empresas)

A NFC-e modelo 65 de mercado não depende desse provedor: ela usa o QR Code e a consulta assistida no portal oficial, com o CAPTCHA resolvido manualmente pelo usuário.

A função não manifesta NF-e automaticamente. Se a distribuição só tiver o resumo `resNFe`, retorna `document_not_complete`.
