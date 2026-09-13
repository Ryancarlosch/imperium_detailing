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
- 🟡 download controlado de novos registros
- ⬜ V2 conflitos concorrentes + CAS
- ⬜ V2 cenários e histórico de simulações
- ⬜ homologação multiaparelho

### 8. Configurações e Usuários
- ⬜ configurações compartilhadas
- ⬜ usuários/perfis finais
- ⬜ permissões cloud por todos os módulos
- ⬜ segunda empresa ponta a ponta

### 9. Arquivos
- ⬜ fotos da OS via Storage
- ⬜ assinatura via Storage
- ⬜ comprovantes financeiros
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
