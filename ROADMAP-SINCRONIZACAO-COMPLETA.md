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
- itens e lotes
- movimentações append-only
- reserva/consumo por OS
- saldo calculado de forma consistente
- alertas em todos os aparelhos

### 6. Financeiro
- contas
- movimentos
- pagamentos/parcelas
- taxas de cartão
- transferências
- recebimento por data real
- operações críticas transacionais no PostgreSQL

### 7. Precificação
- custos fixos
- estrutura
- colaboradores: dados financeiros somente para admin
- regras de precificação
- configuração de horas
- margens e parâmetros

### 8. Configurações/Usuários
- identidade da empresa
- permissões
- usuários
- tema e preferências relevantes
- separação entre dados globais e preferências por aparelho

### 9. Arquivos
- fotos de OS
- logos
- assinaturas
- PDFs quando necessário
- Supabase Storage com RLS
- cache local

### 10. Motor de sincronização
- fila offline
- retry
- idempotência
- device_id
- updated_at/version
- tombstone/arquivamento
- Realtime
- tela de saúde da sincronização
- última sincronização
- conflitos que exigem revisão
- modo offline seguro

### 11. Migração final
- importação completa do SQLite existente
- comparação de contagens/totais
- backup obrigatório antes da migração
- teste em segundo aparelho
- teste funcionário
- teste offline/online
- só depois nuvem vira fonte principal dos módulos migrados
