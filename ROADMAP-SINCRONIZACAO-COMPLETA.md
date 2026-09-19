# Imperium Manager — Sincronização completa

## Estado atual
- Backup automático local: concluído.
- Backup Google Drive: concluído e validado.
- Supabase conectado.
- Supabase Auth + deep link: concluído.
- Empresa + RLS: concluído.
- Colaboradores do Ponto na nuvem: concluído.
- Ponto híbrido: pacote completo preparado para migração/teste.

## Ordem restante

### 1. Ponto/Funcionários
- batida compartilhada entre aparelhos
- horário oficial do servidor
- vínculo funcionário ↔ Supabase Auth
- jornada/configuração compartilhada
- correções e auditoria
- fechamento/reabertura
- espelho SQLite
- Realtime
- provisionamento de conta/dispositivo do funcionário

### 2. Clientes e Veículos
- UUID remoto estável
- importação inicial sem duplicar
- criação/edição em qualquer aparelho
- arquivamento em vez de exclusão destrutiva
- resolução de conflito por atualizado_em/versão

### 3. Agenda
- agenda compartilhada
- alterações em tempo real
- vínculo cliente/veículo
- prevenção de conflito de edição

### 4. Ordem de Serviço
- OS e itens
- serviços/produtos
- responsáveis
- checklist
- datas de entrada/saída
- estados e histórico
- fotos/assinaturas via Storage
- adição de serviços em OS aberta

### 5. Estoque
- 🟢 Upload-only V1 de itens/lotes/movimentacoes preparado
- 🟢 RLS multiempresa + idempotencia por origem
- 🟢 movimentações remotas append-only
- 🟡 Download controlado V2 de novos registros
- 🟡 V2.1 detecção de conflitos concorrentes
- 🟡 V2.2 resolução local/nuvem com auditoria
- 🟡 V3 reserva + consumo + saldo serializado + alertas compartilhados
- ⬜ download controlado/reconciliacao
- 🟡 reserva/consumo compartilhado por OS — V3 desenvolvido
- 🟡 saldo remoto serializado entre aparelhos — V3 desenvolvido
- 🟡 alertas compartilhados de estoque baixo — V3 desenvolvido


### 6. Financeiro
- 🟢 Upload Cloud V1: plano de contas + contas + pagamentos + movimentos
- 🟢 RLS multiempresa e idempotência por origem
- 🟢 nenhuma alteração de saldo local durante upload
- 🟡 V2 download controlado + reconstrução de mapas
- 🟡 V2 conflitos concorrentes + resolução local/nuvem
- 🟡 fornecedores + regras de cartão + transferências Cloud
- 🟢 proteção contra dupla contabilização no download
- 🟡 V3 custos fixos + metas + conciliações Cloud
- 🟡 V3 comprovantes em Storage privado
- 🟡 V3 diagnóstico e conflitos CAS de auxiliares
- ⬜ homologação competência x caixa em dois aparelhos

### 7. Precificação
- 🟢 V1 configuração de margens compartilhada
- 🟢 V1 regra oficial de 220h preservada
- 🟢 V1 catálogo + receita padrão de produtos
- 🟢 V1 custos de mão de obra compartilhados
- 🟢 V1 snapshots de custo/margem/preço sugerido
- 🟢 V2 CAS por atualizado_em
- 🟢 V2 conflitos local x nuvem
- 🟢 V2 resolução usar Local / usar Nuvem
- 🟢 V2 exclusões sincronizadas por soft delete
- 🟢 V2 cenários personalizados
- 🟢 V2 histórico append-only de simulações
- 🟡 UI gerencial de conflitos/cenários
- ⬜ homologação multiaparelho

### 8. Configurações e Usuários
- 🟢 V1 configuração empresarial Cloud
- 🟢 V1 CAS e conflito Local/Nuvem
- 🟢 V1 Central Cloud de diagnóstico
- 🟢 permissões reutilizam `imperium_funcionario_acessos`
- 🟢 módulos remotos: Ponto, Clientes, Agenda, OS, Estoque, Financeiro, Configurações
- 🟡 vínculos multiempresa visíveis
- ⬜ isolamento SQLite por empresa
- ⬜ troca segura de tenant
- ⬜ CRM e Orçamentos como módulos remotos
- ⬜ homologação segunda empresa ponta a ponta

### 9. Arquivos
- 🟢 fotos da OS via Storage privado
- 🟢 assinatura via Storage privado
- 🟢 comprovantes financeiros via Storage privado
- ⬜ documentos fiscais necessários

### 10. Motor de sincronização
- ⬜ fila/retry unificados
- ⬜ diagnóstico de conflitos
- ⬜ Realtime onde fizer sentido
- ⬜ idempotência e observabilidade comuns
- ⬜ política offline por módulo

### 11. Migração final / plataformas
- ⬜ homologação Android multiaparelho
- ⬜ Web
- ⬜ iOS
- ⬜ segunda empresa
- ⬜ suíte completa de contratos e regressão

### Precificação V3 — Central gerencial
- 🟢 visão geral de saúde dos preços;
- 🟢 alertas de margem crítica e abaixo do equilíbrio;
- 🟢 cenários personalizados e histórico;
- 🟢 conflitos Local x Nuvem resolvíveis pela UI;
- 🟢 aplicação individual confirmada do preço sugerido;
- ⬜ homologação real multiaparelho.

### CRM + Orçamentos Cloud
- 🟢 Orçamentos V1 upload/download de novos
- 🟢 itens + perfil de preço
- 🟢 CRM V1 leads/interações
- 🟢 campanhas/cupons compartilhados
- 🟢 soft delete remoto
- 🟢 permissões `crm` e `orcamentos` liberadas no acesso funcionário
- ⬜ V2 CAS e conflitos Local/Nuvem
- ⬜ homologação multiaparelho

### CRM + Orçamentos Cloud V2
- 🟢 alteração concorrente
- 🟢 baseline hash + atualizado_em
- 🟢 autoaplicação quando só nuvem mudou
- 🟢 conflito quando ambos mudaram
- 🟢 CAS ao escolher local
- 🟢 aplicação direta ao escolher nuvem
- 🟢 Central Cloud
- ⬜ homologação multiaparelho

### 9. Arquivos / Storage
- 🟢 bucket privado da OS
- 🟢 fotos Antes/Depois
- 🟢 checklist e foto de avaria
- 🟢 assinatura do cliente
- 🟢 download para cache local Android
- 🟢 SHA-256 e caminhos determinísticos
- 🟢 soft delete de metadados
- 🟢 comprovantes financeiros permanecem no bucket financeiro
- 🟡 conflito simples de assinatura diagnosticado
- ⬜ V2 conflito do checklist
- ⬜ UI de erros/pendências
- ⬜ suporte Web para arquivos
- ⬜ homologação multiaparelho


### 9. Arquivos / Storage V2
- 🟢 reconciliação antes de upload
- 🟢 reconciliação antes de download
- 🟢 conflito concorrente de checklist
- 🟢 conflito concorrente de assinatura
- 🟢 autoaplicação quando só nuvem mudou
- 🟢 CAS ao escolher versão local
- 🟢 resolução pela versão da nuvem
- 🟢 painel na Central Cloud
- ⬜ homologação multiaparelho
- ⬜ retry visual de arquivos
- 🟢 adaptação Web para leitura e escrita de fotos, checklist e assinatura

### 10. Isolamento local multiempresa
- ⬜ separar SQLite por empresa/tenant
- ⬜ troca segura de empresa
- ⬜ limpeza de caches de tenant
- ⬜ garantir mapas de sync isolados

### 10. Multiempresa SQLite isolado
- 🟢 banco físico separado por empresa
- 🟢 adoção não destrutiva do banco legado
- 🟢 tenant resolvido antes da sessão local
- 🟢 troca segura pela Central Cloud
- 🟢 reload do app após troca
- 🟢 backup aponta para tenant ativo
- 🟢 restore bloqueia tenant incorreto
- 🟢 novos arquivos da OS em pasta por tenant
- ⬜ homologação real empresa A ↔ empresa B
- ⬜ limpeza/gestão de tenants locais órfãos

### 11. Motor unificado de sincronização
- ⬜ fila única por módulo
- ⬜ retry/backoff
- ⬜ telemetria
- ⬜ diagnóstico de pendências
- ⬜ observabilidade e homologação

### 12. Web Foundation V1
- 🟢 target Flutter Web
- 🟢 entrypoint Web isolado
- 🟢 Supabase Auth
- 🟢 seleção de empresa/tenant
- 🟢 SQLite WASM + IndexedDB
- 🟢 schema v33 reutilizado
- 🟢 AppDatabase sem `dart:io` direto
- 🟢 build Web release de fundação
- 🟢 Dashboard Web V1
- 🟢 módulos operacionais
- 🟢 arquivos via bytes/Storage privado
- 🟢 PDF/download browser
- ⬜ homologação completa

### 13. Web Operacional V1
- 🟢 Web online-first direto no Supabase
- 🟢 Dashboard Web V1
- 🟢 Clientes Web: cadastro, edição, arquivamento e reativação
- 🟢 Veículos Web: cadastro, edição e exclusão lógica
- 🟢 Agenda Web: cadastro e exclusão lógica
- 🟢 OS Web: consulta, valor negociado e pendente
- 🟢 troca de empresa no shell Web
- 🟢 Android permanece offline-first com Motor Unificado
- 🟢 OS Web completa
- 🟢 Estoque Web
- 🟢 Financeiro/DRE Web
- 🟢 Precificação Web
- 🟢 CRM/Orçamentos Web
- 🟢 arquivos/assinatura Web
- 🟢 PDF/download browser
### 14. Web Gestão V2
- 🟢 criação de OS aberta no Web
- 🟢 múltiplos serviços na nova OS Web
- 🟢 importação posterior da nova OS pelo Android
- 🟢 compensação por soft delete se falhar criação de itens
- 🟢 Estoque Web gerencial
- 🟢 alertas de estoque baixo no Web
- 🟢 Financeiro Web gerencial
- 🟢 saldos por conta a partir de movimentos realizados
- 🟢 entradas/saídas e resultado de caixa do mês
- 🟢 valores a receber via pagamentos Cloud
- 🟢 edição concorrente de OS existente Web ↔ Android
- 🟢 finalização transacional de OS no Web
- 🟢 lançamentos financeiros pelo Web
- 🟢 movimentações de estoque pelo Web
### 15. Web Comercial e Gestão V3
- 🟢 navegação Web escalável com sidebar desktop e drawer mobile
- 🟢 origem Web persistente/idempotente
- 🟢 CRM Web com pipeline, cadastro/edição de lead e interações
- 🟢 edição CRM com CAS por `atualizado_em`
- 🟢 Orçamentos Web multi-itens
- 🟢 status de orçamento com CAS
- 🟢 Precificação Web com regra oficial de 220h/mês da empresa
- 🟢 edição segura de margens por CAS
- 🟢 snapshots de preço e cenários Web
- 🟢 Central Web por tenant com diagnóstico de módulos/permissões
- 🟢 RLS existente continua sendo a autoridade de acesso
- 🟢 edição concorrente de OS existente Web ↔ Android
- 🟢 finalização transacional de OS pelo Web
- 🟢 movimentações de estoque pelo Web
- 🟢 lançamentos financeiros pelo Web
- 🟢 arquivos/checklist/assinatura Web
- 🟢 PDF/download browser

### 16. OS Cloud V3 + edição Web segura
- 🟢 CAS no upload Android de OS e itens já mapeados
- 🟢 CAS também em exclusões remotas publicadas pelo Android
- 🟢 reconciliação de OS existente Web ↔ Android
- 🟢 conflito quando Android e nuvem mudam a mesma OS/item
- 🟢 aplicação automática quando apenas a nuvem mudou
- 🟢 Central Cloud Android mostra e resolve conflitos de OS
- 🟢 edição Web de OS Aberta/Em andamento
- 🟢 edição Web de múltiplos serviços
- 🟢 adição/remoção de serviços numa transação Postgres única
- 🟢 RPC Web usa RLS/security invoker
- 🟢 RPC trava OS/itens e valida `atualizado_em`
- 🟢 `valor_total` recalculado no servidor
- 🟢 assinatura existente fica desatualizada após edição
- 🟢 finalização Web transacional (estoque + financeiro + pagamento)
- 🟢 cancelamento Web com efeitos de negócio
- 🟢 arquivos/checklist/assinatura no navegador

### 17. OS Cloud V4 - finalização transacional Web
- 🟢 contrato Cloud de produtos consumidos pela OS
- 🟢 composição FIFO por lote sincronizável Web ↔ Android
- 🟢 conflitos de contrato de produtos com resolução local/nuvem
- 🟢 finalização Web exige OS `Em andamento`
- 🟢 CAS da OS e do contrato de produtos
- 🟢 idempotência/exactly-once por OS
- 🟢 baixa FIFO no Postgres com lock de estoque
- 🟢 reservas de outras OS respeitadas
- 🟢 prevenção de dupla baixa no sync Android após finalização Web
- 🟢 snapshot de mão de obra com regra oficial de horas produtivas
- 🟢 pagamento opcional, parcial ou total
- 🟢 conta financeira obrigatória quando há recebimento
- 🟢 taxa da maquininha e repasse ao cliente no mesmo commit
- 🟢 recebimento da OS não duplica receita na DRE
- 🟢 taxa de pagamento continua como custo variável na DRE
- 🟢 ajustes financeiros sincronizados para suportar estorno/correção futura
- 🟢 produtos de OS finalizada no Web tornam-se imutáveis
- 🟢 finalização rollback total se qualquer etapa falhar
- 🟢 Central Cloud Android mostra saúde/conflitos do V4
- 🟢 Web ganha página dedicada `Finalizar OS`
- ⬜ homologação real Android ↔ Web em dois dispositivos
- 🟢 cancelamento Web transacional
- 🟢 checklist/fotos/assinatura no navegador

### 18. Paridade funcional Mobile → Web
- 🟢 workspace Web profissional e responsivo
- 🟢 clientes, veículos, agenda e histórico operacional
- 🟢 OS: criação, edição concorrente, cancelamento e finalização transacional
- 🟢 OS: produtos, PDF, fotos, checklist, avarias e assinatura
- 🟢 estoque: produtos, lotes, movimentações, reservas e alertas
- 🟢 financeiro: fluxo de caixa, contas, DRE, relatórios, lançamentos e estornos
- 🟢 gestão financeira: fornecedores, taxas, custos fixos, metas, plano de contas, mão de obra, previsto x realizado e transferências
- 🟢 comercial: CRM, orçamentos, precificação, serviços, pós-venda e marketing
- 🟢 equipe: ponto, funcionários, solicitações e pagamentos
- 🟢 administração: usuários, acessos, empresa, Central Cloud e pendências
- 🟢 fotos e galeria no navegador
- 🟢 fiscal Web com XML Cloud e integração operacional
- 🟡 homologação real Android ↔ Web em dois dispositivos
- 🟡 validação final de todos os perfis/RLS em tenant de homologação

Funções dependentes de hardware ou do sistema operacional continuam nativas por definição: câmera/scanner, notificações locais, backup/restauração do banco local e instalação/atualização do aplicativo. No Web, os resultados sincronizados dessas funções permanecem disponíveis nos módulos correspondentes.
