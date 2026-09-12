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
- ⬜ download controlado/reconciliacao
- ⬜ reserva/consumo compartilhado por OS
- ⬜ saldo consistente entre aparelhos
- ⬜ alertas em todos os aparelhos
