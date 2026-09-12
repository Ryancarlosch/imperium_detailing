# ROADMAP MESTRE — IMPERIUM MANAGER

> Documento permanente de continuidade do projeto.
>
> **Regra principal:** nenhum item antigo deve ser apagado. Quando algo for concluído,
> o item permanece no roadmap e muda de status, recebendo data/notas quando necessário.

Última atualização: **2026-09-10**
## BASELINE OFICIAL — 2026-09-01

- Branch oficial: `desenvolvimento`.
- Baseline anterior à Sprint 0: `1c35d4d` — Financeiro otimizado + OS Cloud Upload-Only V1.
- Financeiro local está avançado e permanece local até homologação completa no APK.
- OS Cloud possui Upload-Only V1 homologado e V2.1 de download controlado apenas de OS/itens novos.
- Consulta por placa existe no app; Edge Function `consultar-placa` está ativa com JWT e requer homologação real APK → Supabase → Falcon.
- Ponto possui dados reais na nuvem; homologação física multiaparelho ainda pendente.
- Ordem imediata: homologar placa com fallback manual → acompanhar OS Cloud V2.1 → homologar Financeiro → fechar Ponto multiaparelho.

---

## 0. Como usar este roadmap

### Status oficiais

- ✅ **Concluído** — implementado e validado no nível indicado.
- 🟢 **Implementado localmente** — existe no SQLite/app local, mas ainda pode faltar sincronização.
- 🟡 **Em desenvolvimento / validação** — implementação parcial ou aguardando teste real.
- ⬜ **Pendente** — ainda não desenvolvido.
- 🛡️ **Protegido** — não alterar sem revisar dependências e impacto multiempresa/sincronização.
- ⚠️ **Correção necessária** — implementação existe, mas há regra/erro conhecido a corrigir.

### Regras de manutenção

1. **Nunca apagar itens concluídos ou antigos.**
2. Toda atualização do aplicativo deve atualizar este arquivo no mesmo patch `.ps1`.
3. Toda nova funcionalidade deve ser adicionada primeiro ao módulo correto deste roadmap.
4. Ao concluir:
   - trocar o status;
   - manter a descrição original;
   - adicionar data e observação curta;
   - registrar a atualização no histórico no final do arquivo.
5. Antes de criar um patch:
   - consultar este roadmap;
   - consultar a branch `desenvolvimento`;
   - confirmar quais arquivos já existem;
   - evitar duplicar services, repositories, tabelas e telas.
6. Nenhum patch deve apagar dados existentes para “resolver” erro.
7. Migrações SQLite devem preservar bancos já instalados.
8. Multiempresa, licença, Supabase Auth, RLS e sincronização de funcionários são áreas protegidas.
9. `flutter analyze`, `flutter test` e `git diff --check` devem passar antes de considerar uma etapa concluída.
10. O branch de desenvolvimento principal é `desenvolvimento`.

---

# 1. REGRAS DE NEGÓCIO IMUTÁVEIS

## 1.1 Jornada e custo da empresa

🛡️ **Regra oficial**

- A empresa trabalha aproximadamente **220 horas por mês**.
- Funcionários trabalham simultaneamente dentro dessas mesmas 220 horas.
- **Não multiplicar 220h pela quantidade de funcionários.**
- Exemplo:
  - empresa: 220 h/mês;
  - proprietário + 2 funcionários: empresa continua 220 h/mês;
  - salários/custos de todos são somados;
  - custo/hora da estrutura = custos mensais totais ÷ 220 h.
- Cada funcionário também pode usar 220 h como base para calcular seu valor/hora individual.

## 1.2 Financeiro

🛡️ **Regra oficial**

- Faturamento por competência e saldo/caixa são conceitos diferentes.
- OS finalizada gera faturamento comercial no período da venda/finalização.
- Pix/dinheiro recebido afeta saldo da conta imediatamente.
- Venda parcelada só afeta saldo conforme cada parcela for realmente recebida.
- Cadeia desejada:
  `OS → pagamento → movimento financeiro → conta → dashboard → relatórios`.
- Taxas da maquininha devem entrar no custo/resultado e precificação.
- Nenhum movimento financeiro pode ser duplicado por sincronização/retry.

## 1.3 Ordem de Serviço

🛡️ **Regra oficial**

- Responsável da OS indica quem executou o serviço.
- Salário e valor/hora do funcionário não aparecem na OS para o cliente.
- Custos de mão de obra são internos.
- Deve ser possível adicionar serviço em OS ainda aberta/em andamento.
- Datas reais de entrada e saída devem ser editáveis.
- Finalização deve preservar estoque, pagamentos e financeiro transacionalmente.

## 1.4 Multiempresa

🛡️ **Regra oficial**

- Dados de empresas diferentes nunca podem se misturar.
- Toda estrutura remota deve respeitar `empresa_id`.
- RLS/RPCs do Supabase devem continuar garantindo isolamento.
- Segunda empresa deve conseguir usar o aplicativo com dados próprios.
- Nenhuma correção local pode hardcodar a Imperium como única empresa.
- Um dispositivo beta atualmente pode ficar vinculado a uma única empresa até evolução planejada.

---


## 1.5 Multiplataforma e identidade única

🛡️ **Regra oficial**

- O Imperium Manager deve evoluir como **um único produto** para Android, Web e iOS.
- O mesmo usuário deve utilizar a **mesma conta Supabase Auth** em todas as plataformas.
- A mesma conta deve manter o mesmo vínculo com empresa, função e permissões.
- Todos os dados remotos devem continuar isolados por `empresa_id` e protegidos por RLS.
- Android, Web e iOS devem enxergar a mesma fonte de verdade na nuvem para os módulos sincronizados.
- O aplicativo não deve criar bancos, usuários ou cadastros independentes por plataforma.
- Funcionalidades novas devem evitar dependência exclusiva de Android quando existir solução Flutter/multiplataforma adequada.
- Recursos específicos de plataforma, como câmera, arquivos, notificações, impressão, biometria e deep links, devem ficar atrás de adapters/services.
- Repositories e regras de domínio devem permanecer independentes da UI e, sempre que possível, independentes de plataforma.
- Offline continua sendo prioridade para Android/iOS quando fizer sentido; Web pode operar prioritariamente online.
- A sequência oficial é:
  1. consolidar cloud e sincronização multi-dispositivo no Android atual;
  2. garantir contratos remotos, RLS, idempotência e conflitos;
  3. adaptar UI/layout para responsividade;
  4. habilitar e homologar Web;
  5. habilitar e homologar iOS;
  6. manter testes de contrato comuns entre as plataformas.
# 2. FUNDAÇÃO, BACKUP E SEGURANÇA

✅ **Backup automático local**
- Concluído antes de 2026-08-13.

✅ **Backup Google Drive**
- Concluído e validado antes de 2026-08-13.

✅ **Supabase conectado**
- Bootstrap e chave publishable de cliente configurados.

✅ **Supabase Auth + deep link**
- Concluído.

✅ **Empresa + RLS**
- Estrutura de empresa e isolamento por RLS concluídos no estágio atual.

🛡️ **Licença da empresa**
- Existe `LicencaService`.
- Valida licença pela nuvem.
- Possui cache offline temporário.
- Vincula instalação/dispositivo à empresa.
- **Não alterar em patches de módulos sem revisão específica.**

🛡️ **Acesso de funcionário**
- Existe `FuncionarioAcessoService`.
- Magic Link/Supabase Auth.
- Vínculo colaborador local ↔ remoto.
- Permissões remotas.
- Dispositivo do funcionário.
- **Não alterar indiretamente por patches de financeiro/precificação/OS.**

⬜ **Auditoria completa de segredos do repositório**
- Verificar ausência de `service_role`, senha de banco, private keys e outros segredos.

---

# 3. LOGIN, USUÁRIOS, PERMISSÕES E LICENÇA

🟢 **Login local**
- Usuário/senha implementados.

🟢 **Sessão persistente / manter conectado**
- Fluxo de persistência/restauração já implementado na branch atual.
- Necessita continuar sendo testado em APK real.

🟢 **Administrador com acesso total**
- Regra existente.

🟢 **Permissões por módulo**
- Estrutura existente.

🟡 **Permissões do funcionário sincronizadas com nuvem**
- Implementação existe.
- Requer validação completa em segundo aparelho/conta.

🟡 **Primeiro acesso da empresa**
- Tela/fluxo existem.
- Validar ponta a ponta com uma segunda empresa real/teste.

🟡 **Primeiro acesso do funcionário**
- Tela/fluxo existem.
- Validar Magic Link, dispositivo, permissões e bloqueio/revogação.

⬜ **Teste multiempresa completo**
- Empresa A não enxerga dados da Empresa B.
- Empresa B consegue ser criada/liberada.
- Licença independente.
- Usuários independentes.
- Funcionários independentes.

---

# 4. PONTO E FUNCIONÁRIOS — PRIORIDADE ATUAL

> Esta é a primeira etapa da ordem oficial de sincronização.

✅ **Tabela/jornada local do ponto**
- `financeiro_ponto_jornada`.
- Segunda a sexta + sábado configuráveis.
- Erro antigo de tabela ausente/SELECT inválido já foi corrigido no código atual.

✅ **Registros locais de ponto**
- Entrada.
- Intervalo.
- Saída.
- Situação do dia.

✅ **Ajustes/auditoria local**
- Histórico de ajustes implementado.

✅ **Configuração de hora extra**
- Percentual configurável.

✅ **Fechamento/reabertura de competência local**
- Estruturas e histórico implementados.

✅ **Estimativa de folha pelo ponto**
- Salário base.
- horas extras.
- horas faltantes.
- valores já pagos.
- saldo estimado.

✅ **Pagamento de funcionário no financeiro**
- Movimento de saída.
- conta financeira.
- vínculo com registro do pagamento.
- `numero_documento` não nulo corrigido.

✅ **Ponto na nuvem**
- Estrutura/RPCs preparada.
- Usa horário oficial do servidor.
- Proteções por empresa/usuário.

🟡 **Ponto híbrido offline + nuvem**
- Pacote preparado.
- Falta validação final completa em aparelhos reais.

🟡 **Vínculo funcionário ↔ Supabase Auth**
- Implementado parcialmente/estrutura pronta.
- Validar ativação, revogação e reinstalação.

🟡 **Batida compartilhada entre aparelhos**
- Implementação de nuvem preparada.
- Proteção V5: duas batidas do mesmo minuto não avançam o estado por engano.
- RPC offline idempotente passou a fazer parte do SQL mestre versionado.
- Falta aplicar/verificar o SQL no Supabase e validar em dois aparelhos reais.

🟡 **Jornada/configuração compartilhada**
- Validar se todos os aparelhos recebem a mesma configuração corretamente.

🟡 **Espelho SQLite ↔ nuvem**
- Validar consistência e recuperação offline.

⬜ **Realtime do ponto**
- Confirmar atualização automática sem reabrir a tela.

⬜ **Teste completo do funcionário**
- Login próprio.
- permissões.
- bater ponto.
- offline.
- voltar online.
- sincronizar sem duplicar.
- administrador editar.
- fechamento.

### Critério para marcar módulo Ponto/Funcionários como concluído

- Segundo aparelho funcionando.
- Funcionário autenticado.
- empresa correta.
- horário do servidor.
- offline/online sem duplicar batida.
- permissões respeitadas.
- fechamento mensal consistente.
- pagamento não duplica movimento financeiro.

---

# 5. CLIENTES E VEÍCULOS

🟢 **CRUD local de clientes**
- Implementado.

🟢 **CRUD local de veículos**
- Implementado.

🟢 **Arquivamento de clientes**
- Estrutura existe.

🟡 **Sincronização operacional de clientes**
- `OperacionalSyncService` já possui mapeamento local/remoto por empresa.

🟡 **Sincronização operacional de veículos**
- Estrutura existe.

🟡 **UUID remoto estável**
- Mapeamentos remotos existem.
- Validar todos os casos de importação/múltiplos aparelhos.

🟡 **Importação inicial sem duplicar**
- Implementação existe.
- Requer teste de migração com dados reais.

🟡 **Criação/edição em qualquer aparelho**
- Validar conflito.

⬜ **Resolução formal de conflitos por versão/updated_at**
- Ainda parte do motor completo.

⬜ **Teste Empresa A x Empresa B**
- Mesmo nome/placa não deve causar cruzamento entre tenants.

---

# 6. AGENDA

🟢 **Agenda local**
- Implementada.

🟢 **Vínculo cliente/veículo**
- Implementado localmente.

🟡 **Agenda compartilhada via Supabase**
- Estrutura operacional já preparada.

🟡 **Alterações entre aparelhos**
- Validar criação/edição/importação.

⬜ **Realtime completo**
- Atualização automática.

⬜ **Prevenção de conflito de edição**
- Estratégia por versão/updated_at.

---

# 7. ORDENS DE SERVIÇO

🟢 **Criação de OS**
- Implementada.

🟢 **Itens/serviços da OS**
- Implementados.

🟢 **Responsável**
- Implementado.

🟢 **Checklist**
- Implementado.

🟢 **Fotos**
- Implementadas localmente.

🟢 **Assinatura**
- Implementada localmente.

🟢 **Produtos utilizados**
- Implementados.

🟢 **Baixa de estoque na finalização**
- Implementada.

🟢 **Entrada/saída editáveis**
- Fluxo existe na versão atual.

🟢 **Adicionar serviço em OS aberta**
- Repository e UI possuem fluxo específico para OS Aberta/Em andamento.

🟢 **Pagamento/finalização**
- Fluxos locais implementados.

- ✅ **Sincronização de OS — Upload-Only V1**
- 🟢 OS e itens possuem upload idempotente para o Supabase.
- ✅ Homologado conforme validação atual; manter homologação real de retry/idempotência e isolamento por empresa.
- ⬜ Checklist/revisões na nuvem.
- ⬜ Serviços/produtos/responsáveis/histórico conforme arquitetura cloud.
- 🟡 **OS Cloud V2.1 — download controlado de registros novos**
- 🛡️ Importa somente OS/itens remotos sem mapa, após clientes, veículos e agenda.
- 🛡️ Não sobrescreve OS mapeada e não baixa pagamentos, estoque, produtos, fotos, assinatura, checklist ou revisões.
⬜ **Fotos/assinaturas no Supabase Storage**
- Preservar cache local.

⬜ **Conflitos de edição entre aparelhos**
- Necessita motor de versão.

---

# 8. ESTOQUE

🟢 **Itens de estoque**
- Implementados localmente.

🟢 **Movimentações**
- Implementadas.

🟢 **Lotes**
- Estrutura local existente.

🟢 **Uso/baixa por OS**
- Implementado.

🟢 **Alertas**
- Dashboard possui alertas locais.

⬜ **Sincronização dos itens**
- Por empresa.

⬜ **Movimentações append-only na nuvem**
- Evitar reescrever histórico.

⬜ **Reserva/consumo multiaparelho**
- Consistência transacional.

⬜ **Saldo idêntico em todos aparelhos**
- Critério obrigatório.

---

# 9. FINANCEIRO

🟢 **Plano de contas**
- Implementado.

🟢 **Contas financeiras**
- Implementadas.

🟢 **Saldo real calculado por conta**
- saldo inicial + movimentos realizados.

🟢 **Dashboard com saldo total/por conta**
- Implementado.

🟢 **Ocultar valores com botão de olho**
- Implementado no Dashboard.

🟢 **Movimentos financeiros**
- Entrada/saída/previsto/realizado.

🟢 **Contas a receber**
- Implementadas.

🟢 **Pagamentos da OS**
- Implementados.

🟢 **Parcelas**
- Estrutura e regras implementadas.

🟢 **Recebimento por data real**
- Fluxos locais usam data de pagamento.

🟢 **Taxas de cartão no pagamento**
- Repository registra taxa de operação.

🟢 **Taxa da maquininha como saída**
- Movimento financeiro específico implementado.

🟢 **Pagamento de funcionários**
- Integrado às contas/movimentos.

🟢 **Transferências**
- Estrutura local existente.

🟢 **Conciliação de conta**
- Estrutura implementada.

🟢 **DRE / competência x caixa**
- Estrutura local implementada.

✅ **Relatórios financeiros**
- Consolidados em 2026-09-10.
- `relatorios_financeiros_page.dart` permanece como tela oficial.
- A cópia temporária `_corrigido` foi removida somente após validação de conteúdo idêntico.
- Teste-fonte impede a reintrodução da duplicidade.

⬜ **Sincronização financeira Supabase**
- contas.
- movimentos.
- pagamentos.
- parcelas.
- taxas.
- transferências.

⬜ **Operações críticas em PostgreSQL transacional**
- Recebimento.
- estorno.
- taxa.
- transferência.
- evitar duplicidade por retry.

⬜ **Teste financeiro multiempresa**
- movimentos/contas nunca cruzam tenants.

---

# 10. MAQUININHA DE CARTÃO

🟢 **Regras de taxa**
- Estrutura local existente.

🟢 **Nome da regra**
- Implementado.

🟢 **Débito**
- Taxa específica.

🟢 **Crédito**
- Parcelas até 12x.

🟢 **Taxa por quantidade de parcelas**
- Implementada.

🟢 **Conta própria da maquininha**
- Vínculo com conta do tipo Maquininha.

🟢 **Aplicação automática da taxa em pagamento**
- PagamentoRepository possui regra automática.

⬜ **Sincronização das regras por empresa**
- Deve fazer parte do Financeiro/Configurações remotas.

⬜ **Teste completo**
- débito.
- crédito 1x.
- parcelado.
- taxa absorvida.
- valor líquido.
- DRE.
- saldo da conta.

---

# 11. PRECIFICAÇÃO E CUSTOS

🟢 **Custos fixos**
- Implementados.

🟢 **Colaboradores/custos**
- Implementados.

🛡️ **Carga horária da empresa = 220h/mês**
- Não multiplicar pelo número de funcionários.

🟡 **Correção da semântica de horas**
- Garantir que o código continue tratando 220h como jornada da empresa.

🟢 **Custo de produtos por serviço**
- Implementado.

🟢 **Custo de estrutura**
- Implementado.

🟢 **Custo/hora**
- Implementado, sujeito à regra correta das 220h.

🟢 **Histórico financeiro como base de custo**
- Precificação possui uso de média histórica.

🟢 **Taxa média de cartão**
- Precificação considera taxas.

🟢 **Tempo previsto e tempo real**
- Estruturas implementadas.

🟢 **Preço de equilíbrio**
- Implementado.

🟢 **Preço mínimo seguro**
- Implementado.

🟢 **Preço sugerido**
- Implementado.

🟢 **Margens cliente/revenda**
- Implementadas.

🟢 **Faixas de revenda**
- 1–4.
- 5–9.
- 10+.

🟡 **Resultado real por OS**
- Produtos + taxas + mão de obra + rateio fixo existem.
- Validar regra das 220h e exemplos reais.

⬜ **Sincronização da precificação**
- Somente depois do Financeiro na ordem oficial.

⬜ **Dados financeiros de colaborador somente admin**
- Validar também na nuvem/RLS.

---

# 12. DASHBOARD

🟢 **Resumo operacional**
- clientes.
- veículos.
- OS.
- agenda.

🟢 **Saldo financeiro real**
- total e por conta.

🟢 **Faturamento por competência**
- separado das entradas realizadas.

🟢 **Entradas/saídas por período**
- implementadas.

🟢 **Lucro bruto estimado**
- implementado.

🟢 **Gráficos**
- implementados.

🟢 **Ranking de serviços/clientes**
- implementado.

✅ **Correção do ranking de serviços pelo valor líquido da OS**
- Corrigido em 2026-09-10.
- O ranking deixa de somar o valor bruto dos itens quando a OS possui desconto.
- Desconto, desconto de negociação, acréscimo e juros da OS são rateados proporcionalmente entre os serviços pelo valor bruto de cada item.
- A soma dos valores do ranking permanece coerente com o faturamento por competência das OS finalizadas.
- Caso validado: serviço de R$ 600 com desconto de R$ 250 passa a contabilizar R$ 350 no ranking.

🟢 **Alertas**
- agenda.
- OS.
- estoque.

🟢 **Ocultar saldos**
- implementado.

🟡 **Permissões por módulo no Dashboard**
- Estrutura existe.
- Revisar Ponto e demais atalhos para usar a chave correta.

⬜ **Dashboard multiempresa validado**
- Deve refletir somente dados do tenant atual.

---

# 13. CONFIGURAÇÕES E USUÁRIOS

🟢 **Configurações locais**
- Implementadas.

🟢 **Identidade da empresa local**
- Implementada.

🟢 **Usuários locais**
- Implementados.

🟢 **Permissões locais**
- Implementadas.

⬜ **Sincronizar identidade da empresa**
- Nome/logo/config relevantes.

⬜ **Sincronizar usuários/permissões administrativas**
- Preservar diferenças entre administrador e funcionário.

⬜ **Separar preferências globais e por aparelho**
- Tema/preferências locais não devem necessariamente sincronizar.

---

# 14. ARQUIVOS E STORAGE

🟢 **Fotos locais**
- Implementadas.

🟢 **Assinaturas locais**
- Implementadas.

🟢 **PDFs locais**
- Implementados.

⬜ **Supabase Storage**
- fotos OS.
- logos.
- assinaturas.
- arquivos necessários.

⬜ **RLS de arquivos**
- Isolamento por empresa.

⬜ **Cache offline**
- Arquivo remoto deve continuar disponível quando apropriado.

---

# 15. MOTOR DE SINCRONIZAÇÃO

🟡 **Mapeamentos local/remoto**
- Clientes, veículos, agenda e ponto possuem estruturas próprias.

🟡 **device_id**
- Implementado em serviços atuais.

🟡 **Offline-first**
- Serviços tentam não bloquear SQLite quando Supabase está indisponível.

⬜ **Fila offline genérica**
- Operações pendentes persistidas.

⬜ **Retry**
- Com backoff.

⬜ **Idempotência**
- Obrigatória em operações críticas.

⬜ **updated_at/version**
- Resolução consistente.

⬜ **Tombstone/arquivamento**
- Evitar delete destrutivo.

⬜ **Realtime**
- Atualização automática.

⬜ **Tela de saúde da sincronização**
- última sincronização.
- pendências.
- erros.
- conflitos.

⬜ **Revisão manual de conflito**
- Quando não for possível resolver automaticamente.

---

# 16. MIGRAÇÃO FINAL PARA NUVEM

⬜ **Backup obrigatório antes da migração**

⬜ **Importação completa do SQLite existente**

⬜ **Comparação de contagens**
- clientes.
- veículos.
- OS.
- estoque.
- movimentos.
- pagamentos.

⬜ **Comparação de totais financeiros**

⬜ **Teste em segundo aparelho**

⬜ **Teste funcionário**

⬜ **Teste offline → online**

⬜ **Teste Empresa A x Empresa B**

⬜ **Somente depois tornar nuvem fonte principal dos módulos migrados**

---

# 17. QUALIDADE TÉCNICA

🟢 **Testes automatizados existentes**
- Projeto possui suite atual.

🟡 **Flutter Analyze**
- Há histórico de issues/warnings técnicos.
- Não aumentar warnings.
- Corrigir aviso do arquivo sempre que ele for alterado.

⬜ **Eliminar pendências técnicas antigas**
- `DropdownButtonFormField value → initialValue`.
- `withOpacity → withValues`.
- widgets não utilizados.
- underscores desnecessários.
- null-aware desnecessário.

🛡️ **Regra de release**
- `dart format`.
- `flutter analyze`.
- `flutter test`.
- `git diff --check`.
- backup.
- atualização sem desinstalar.
- smoke test.
- teste manual crítico.

---

# 18. ORDEM OFICIAL DE DESENVOLVIMENTO / SINCRONIZAÇÃO

Esta ordem não deve ser pulada sem registrar explicitamente o motivo neste roadmap:

1. 🟢 **Ponto/Funcionários — implementação concluída; homologação de campo pendente**
2. 🟡 **Clientes e Veículos**
3. 🟡 **Agenda**
4. 🟡 **Ordem de Serviço na nuvem — Upload-Only V1 implementado; homologação pendente**
5. ⬜ **Estoque na nuvem**
6. ⬜ **Financeiro na nuvem**
7. ⬜ **Precificação na nuvem**
8. ⬜ **Configurações/Usuários**
9. ⬜ **Arquivos/Storage**
10. ⬜ **Motor de sincronização completo**
11. ⬜ **Migração final**

---

# 19. PRÓXIMA AÇÃO OFICIAL

## Etapa atual: Ponto/Funcionários

Próximo trabalho deve começar por:

1. validar o código atual da sincronização de funcionários;
2. validar a empresa/tenant retornado para o funcionário;
3. validar Magic Link;
4. validar dispositivo;
5. validar permissões;
6. testar batida no servidor;
7. testar offline;
8. reconectar e confirmar ausência de duplicidade;
9. validar edição administrativa;
10. validar fechamento e folha estimada;
11. somente então marcar Ponto/Funcionários como ✅ concluído e avançar para Clientes/Veículos.

---

# 20. ARQUIVOS/ÁREAS PROTEGIDOS

Antes de alterar qualquer um destes blocos, revisar impacto e dependências:

- `lib/services/funcionario_acesso_service.dart`
- `lib/services/licenca_service.dart`
- `lib/services/supabase_bootstrap.dart`
- `lib/services/ponto_nuvem_service.dart`
- `lib/services/ponto_offline_sync_service.dart`
- `lib/services/operacional_sync_service.dart`
- `lib/repositories/ponto_sincronizado_repository.dart`
- SQL/RPCs do Supabase
- RLS
- tabelas de vínculo de empresa/dispositivo
- `empresa_id`
- `auth_user_id`
- `dispositivo_id`
- deep links
- primeiro acesso de empresa
- primeiro acesso de funcionário

**Regra:** patch de outro módulo não deve modificar esses arquivos incidentalmente.

---


# 18. PLATAFORMAS — ANDROID, WEB E IOS

> Diretriz oficial: o Imperium deve ser o mesmo sistema, com a mesma conta, empresa, permissões e dados em qualquer plataforma.

🟢 **Android**
- Plataforma operacional principal durante a fase atual.
- SQLite/offline e integração com Supabase continuam sendo consolidados primeiro aqui.
- Homologações reais atuais permanecem prioritárias.

⬜ **Base cloud pronta para multiplataforma**
- Todos os módulos estratégicos devem possuir contrato remoto estável.
- `empresa_id` obrigatório nos dados compartilhados.
- RLS/RPCs e idempotência validadas.
- Tratamento de conflitos/versionamento definido.
- Arquivos/fotos devem usar Storage quando entrarem na etapa oficial de cloud.
- Nenhuma plataforma pode depender de IDs locais SQLite como identidade global.

⬜ **Flutter Web**
- Reutilizar domínio, repositories e contratos já existentes.
- Criar layout responsivo para monitor/notebook.
- Priorizar Dashboard, Financeiro, DRE, relatórios, estoque, clientes, agenda e OS.
- Login deve usar a mesma conta Supabase Auth do Android/iOS.
- Permissões e empresa devem ser as mesmas do usuário autenticado.
- Validar impressão/PDF, upload/download de arquivos e navegação Web.
- Web será habilitado somente após a base cloud dos módulos necessários estar estável.

⬜ **iOS**
- Reutilizar a mesma base Flutter e os mesmos contratos de domínio/cloud.
- Login deve usar a mesma conta Supabase Auth.
- Mesma empresa, permissões e dados de Android/Web.
- Adaptar apenas integrações específicas de plataforma quando necessário.
- Validar câmera, fotos, assinatura, notificações, arquivos, deep links e login no ecossistema Apple.

⬜ **Paridade multiplataforma**
- Usuário cria/edita informação no Web e vê no Android/iOS.
- Usuário cria/edita no Android/iOS e vê no Web.
- Funcionário mantém as mesmas permissões em todos os dispositivos autorizados.
- Alteração de permissão/revogação deve refletir nas demais plataformas.
- Nenhuma duplicação causada por sincronização entre plataformas.
- Teste multiempresa obrigatório em Android + Web + iOS antes de produção ampla.

### Gate para iniciar Web/iOS

Antes de abrir desenvolvimento de produção para Web/iOS, validar:
- Clientes/Veículos cloud;
- Agenda cloud;
- OS cloud;
- Estoque cloud;
- Financeiro cloud;
- Precificação/configurações cloud;
- Auth/permissões/empresa estáveis;
- estratégia de arquivos/Storage;
- retry/idempotência/conflitos;
- testes multi-dispositivo aprovados.

### Princípio técnico

```text
Flutter UI por plataforma
        ↓
Domínio / regras de negócio compartilhadas
        ↓
Repositories / serviços
        ↓
Supabase Auth + PostgreSQL + RLS + Storage
        ↓
mesma empresa / mesmos dados / mesmas permissões
```

SQLite continua como cache/base offline de dispositivos móveis enquanto a arquitetura exigir.
O Supabase será a fonte compartilhada para sincronização entre plataformas.
# 21. HISTÓRICO PERMANENTE
## 2026-09-11 - Sprint 1A - Parte B SQL financeiro

Status: ✅ implementado para validacao.

- Dashboard, ticket medio e rankings usam o contrato monetario unico;
- contas a receber usam o contrato unico;
- status de pagamento usa o contrato unico;
- resumos de cliente e veiculo usam o contrato unico;
- DRE mantem bruto/deducoes separados com liquido equivalente ao contrato;
- criado teste de equivalencia Dart x SQLite;
- schema permanece v33;
- nenhuma migration;
- nenhuma alteracao em Auth, Licenca, RLS, Ponto cloud ou sync de funcionario.

Proxima etapa:
- Sprint 1B: teste ponta a ponta `OS -> pagamento -> movimento -> conta -> Dashboard -> DRE/relatorios`.

---
## 2026-09-11 - Sprint 1A - contrato monetario da OS

Status: Parte A preparada para validacao.

- camada `lib/domain/` iniciada;
- regra unica do valor comercial da OS;
- model, pagamentos, custos e finalizacao usam o mesmo contrato;
- schema permanece v33;
- nenhuma migration;
- nenhuma alteracao em Auth, Licenca, RLS, Ponto cloud ou sync de funcionario;
- Parte B migrara os SQLs de Dashboard/Financeiro/DRE.

---

## 2026-08-13 — Roadmap mestre criado

- Criado documento único de continuidade do projeto.
- Preservada a ordem do `ROADMAP-SINCRONIZACAO-COMPLETA.md`.
- Registrado estado já conhecido dos módulos locais.
- Registrada proteção de multiempresa/licença/sincronização de funcionários.
- Registrada regra oficial de **220 h/mês da empresa**, sem multiplicação pelo número de funcionários.
- Definido que todo patch futuro deve atualizar este roadmap.
- Próxima etapa oficial mantida como **Ponto/Funcionários**.

---


## 2026-08-14 — Correção Dashboard menu e privacidade v2

Módulo: Dashboard / Interface
Status: 🟡 Em evolução

Alterações:
- hamburger ☰ explícito no AppBar;
- menu lateral com Operação, Financeiro e Sistema;
- atalhos financeiros diretos para Receita, Fluxo de caixa, Movimentações e DRE;
- valores iniciam ocultos;
- saldos e gráficos não renderizam enquanto a privacidade estiver ativa;
- teste automatizado impede gerar APK sem os marcadores da nova interface.

Impacto em banco/sincronização/multiempresa:
- nenhum.

---

## 2026-08-13 — Revogação e permissões antes da abertura v3

Módulo: Ponto/Funcionários
Status anterior: 🟡 Em desenvolvimento / validação
Status novo: 🟡 Em desenvolvimento / validação

Alterações:
- sessão persistida de funcionário é validada antes de liberar a interface;
- permissões remotas são sincronizadas no startup quando a nuvem está disponível;
- aparelho revogado encerra a sessão persistida antes da área do funcionário abrir;
- acesso desativado pelo administrador também bloqueia a sessão restaurada;
- em modo offline, a autorização local previamente válida continua disponível;
- após atualizar permissões, a sessão é reconstruída antes da UI.

Arquivos principais alterados:
- lib/main.dart
- ROADMAP-IMPERIUM-MESTRE.md

Banco/migração:
- nenhuma alteração de schema;
- nenhum dado operacional apagado.

Impacto na sincronização:
- não altera fila, RPCs ou RLS;
- apenas antecipa a validação que já ocorria dentro de UsuarioInicioPage.

Impacto multiempresa:
- nenhum novo vínculo é criado;
- preserva empresa/dispositivo já vinculados;
- revogação não troca tenant e não apaga histórico.

Testes:
- flutter analyze: executar pelo imperium.ps1;
- flutter test: executar pelo imperium.ps1;
- teste manual: alterar permissões, fechar/reabrir app do funcionário e confirmar novo menu;
- teste manual: revogar celular, fechar/reabrir e confirmar que área do funcionário não abre;
- teste manual: sem internet, confirmar que sessão local previamente válida continua abrindo.

Próximo passo:
- validar permissões e revogação em aparelho real;
- validar segundo aparelho;
- revisar batida compartilhada e duplicidade final;
- então concluir Ponto/Funcionários.

---

## 2026-08-14 — Correção Realtime V4B

Módulo: Ponto/Funcionários
Status: 🟡 Em validação

Motivo:
- V4 original parou por anchor incompatível com meu_ponto_page.dart local;
- serviço Realtime havia sido criado parcialmente.

Alterações:
- serviço Realtime regravado com API conhecida e tenant obtido por PontoNuvemService;
- colaborador remoto resolvido com empresa_id;
- assinatura filtrada por colaborador_id;
- debounce de 400 ms;
- falha do Realtime não bloqueia offline nem atualização manual;
- Meu Ponto cancela a assinatura ao sair;
- indicador discreto aparece quando a assinatura está ativa.

Impacto multiempresa:
- empresa atual é validada antes de resolver o colaborador remoto;
- nenhum acesso remove ou relaxa empresa_id/RLS.

---

## 2026-08-13 — Idempotência da batida e proteção multiaparelho v5

Módulo: Ponto/Funcionários
Status anterior: 🟡 Em desenvolvimento / validação
Status novo: 🟡 Em desenvolvimento / validação

Alterações:
- SQL mestre agora contém a RPC ponto_registrar_batida_offline usada pelo aplicativo;
- criada tabela ponto_batidas_idempotencia com chave por empresa;
- retry com a mesma chave retorna o resultado original sem gerar nova batida;
- reutilização da mesma chave com conteúdo diferente é bloqueada;
- duas batidas online/offline no mesmo minuto do mesmo funcionário são tratadas como repetição;
- advisory locks continuam serializando operações do mesmo funcionário/dia;
- teste automatizado garante que a RPC offline permaneça no SQL versionado.

Arquivos principais alterados:
- imperium_supabase_ponto_operacoes.sql
- test/ponto_sql_idempotencia_source_test.dart
- ROADMAP-IMPERIUM-MESTRE.md

Banco/migração:
- nenhuma alteração no SQLite;
- SQL remoto adiciona somente tabela de idempotência e RPC segura;
- não apaga registros existentes de ponto.

Impacto na sincronização:
- retry da fila offline deixa de poder duplicar uma mesma chave;
- batida simultânea no mesmo minuto não avança Entrada/Intervalo/Saída indevidamente.

Impacto multiempresa:
- chave de idempotência é composta por empresa_id + chave;
- RPC exige acesso à empresa e valida colaborador dentro do tenant;
- nenhuma empresa consegue reaproveitar estado de idempotência de outra.

Testes:
- flutter analyze: executar pelo imperium.ps1;
- flutter test: executar pelo imperium.ps1;
- pendente: aplicar/verificar SQL atualizado no Supabase;
- pendente: teste real com dois aparelhos no mesmo minuto;
- pendente: teste offline → online repetindo a mesma fila.

Próximo passo:
- aplicar/verificar o SQL V5 no Supabase;
- testar dois aparelhos e retry offline;
- se aprovado, marcar Ponto/Funcionários como concluído;
- avançar oficialmente para Clientes/Veículos.

---

## 2026-08-13 — Diagnóstico de saúde do Ponto na nuvem v6

Módulo: Ponto/Funcionários
Status anterior: 🟡 Em desenvolvimento / validação
Status novo: 🟡 Em desenvolvimento / validação

Alterações:
- criada RPC somente leitura ponto_diagnostico;
- backend do Ponto passa a expor versão 6 e capacidades instaladas;
- diagnóstico valida empresa da sessão antes de consultar recursos;
- verifica RPC online, RPC offline idempotente, tabela de idempotência, Realtime, sync_estado e migração;
- tela Ponto na nuvem recebeu card Saúde da nuvem;
- backend antigo ou SQL ainda não aplicado aparece como atenção, nunca como concluído;
- testes garantem que outra empresa não pode ser considerada saudável.

Arquivos principais alterados:
- imperium_supabase_ponto_operacoes.sql
- lib/services/ponto_nuvem_diagnostico_service.dart
- lib/screens/ponto_nuvem_importacao_page.dart
- test/ponto_nuvem_diagnostico_service_test.dart
- ROADMAP-IMPERIUM-MESTRE.md

Banco/migração:
- nenhuma alteração SQLite;
- RPC ponto_diagnostico é somente leitura;
- nenhum dado remoto é alterado pelo diagnóstico.

Impacto na sincronização:
- permite confirmar no próprio app se o backend necessário à sincronização está realmente implantado;
- não cria registros e não altera fila.

Impacto multiempresa:
- empresa da tela precisa coincidir com empresa da sessão;
- RPC usa usuario_tem_acesso_empresa;
- diagnóstico de tenant diferente é bloqueado.

Testes:
- flutter analyze: executar pelo imperium.ps1;
- flutter test: executar pelo imperium.ps1;
- pendente: aplicar SQL mestre atualizado no Supabase;
- pendente: abrir Ponto na nuvem e obter todos os itens verdes;
- pendente: validar em dois aparelhos.

Próximo passo:
- aplicar/verificar SQL V6 no Supabase;
- confirmar card Saúde da nuvem totalmente verde;
- validar dois aparelhos;
- marcar Ponto/Funcionários como concluído;
- iniciar Clientes/Veículos.

---

## 2026-08-13 — Pacote final de implementação da Etapa 1 v7

Módulo: Ponto/Funcionários
Status anterior: 🟡 Em desenvolvimento / validação
Status novo: 🟢 Implementação concluída / homologação de campo pendente

Alterações:
- criado serviço único de homologação da Etapa 1;
- criada tela Homologação da Etapa 1 dentro de Ponto na nuvem;
- diagnóstico automático exige backend saudável, migração, Realtime, idempotência, fila offline zerada e tenant local correto;
- valida se existem mapeamentos locais do Ponto pertencentes a outra empresa;
- checklist manual obrigatório registra testes de dois aparelhos, offline→online, revogação, permissões e isolamento multiempresa;
- a tela só mostra Etapa 1 homologada quando verificações automáticas e manuais estiverem aprovadas;
- teste de integridade garante presença dos serviços, SQL e recursos críticos.

Arquivos principais alterados:
- lib/services/ponto_etapa1_validacao_service.dart
- lib/screens/ponto_etapa1_validacao_page.dart
- lib/screens/ponto_nuvem_importacao_page.dart
- test/ponto_etapa1_integridade_test.dart
- ROADMAP-IMPERIUM-MESTRE.md

Banco/migração:
- cria apenas imperium_ponto_validacao_etapa1 no SQLite;
- tabela guarda checklist de homologação por empresa;
- nenhum registro operacional de Ponto é apagado ou alterado.

Impacto na sincronização:
- nenhuma nova gravação remota;
- homologação apenas consulta diagnóstico/fila e lê vínculos locais.

Impacto multiempresa:
- homologação é persistida por empresa_id;
- exige que os vínculos locais pertençam ao tenant esperado;
- reprova se encontrar mapeamento de Ponto de outra empresa na mesma instalação.

Testes:
- flutter analyze: executar pelo imperium.ps1;
- flutter test: executar pelo imperium.ps1;
- homologação automática: executar pela tela Ponto na nuvem;
- homologação manual: dois aparelhos, offline→online, revogação, permissões, Empresa A x Empresa B.

Critério final:
- implementação da Etapa 1 está concluída;
- somente marcar Ponto/Funcionários como ✅ Homologado após todos os itens da tela ficarem aprovados;
- desenvolvimento pode seguir para melhorias de interface sem alterar a ordem da migração dos módulos.

Próximo passo:
- modificar a tela inicial/dashboard conforme solicitado;
- depois retomar a ordem oficial com Clientes/Veículos quando a homologação da Etapa 1 estiver registrada.

---

## 2026-08-14 — Ponto rápido para dias anteriores v1

Módulo: Ponto/Funcionários
Status: 🟡 Em validação

Alterações:
- criado atalho Ponto rápido de dia anterior;
- administrador escolhe funcionário e data passada;
- sistema usa automaticamente a jornada programada do dia da semana;
- entrada, intervalo, volta e saída são preenchidos conforme Jornada padrão;
- dias sem jornada ativa são bloqueados;
- data atual e datas futuras não são aceitas;
- registro existente nunca é sobrescrito pelo atalho;
- lançamento usa salvarRegistro do PontoSincronizadoRepository, preservando a rota de nuvem quando o Ponto híbrido estiver ativo;
- observação e motivo identificam o lançamento como Ponto rápido.

Regra de segurança:
- competência fechada continua bloqueada;
- qualquer correção de registro já existente continua manual e auditada;
- nenhuma regra de autenticação, RLS, empresa_id ou idempotência de batida foi alterada.

Impacto multiempresa:
- nenhum desvio novo; o lançamento administrativo segue a resolução de empresa já existente no Ponto sincronizado.

---

## 2026-08-14 — Correção cadastro multiempresa — slug obrigatório v1

Módulo: Configurações/Usuários • Multiempresa
Status: 🟡 Em validação

Problema identificado:
- painel Nova empresa chamava corretamente imperium_admin_criar_empresa_beta;
- a RPC delegava para imperium_admin_criar_cliente;
- imperium_admin_criar_cliente inseria somente nome e ativo em public.empresas;
- public.empresas exige slug NOT NULL;
- cadastro falhava com PostgreSQL 23502.

Correção backend:
- imperium_admin_criar_cliente passa a gerar slug único;
- slug é derivado do nome e recebe sufixo curto do UUID da empresa;
- ID da empresa é criado antes do INSERT;
- demais regras de licença, convite e histórico permanecem inalteradas.

Segurança:
- private.imperium_eh_admin_comercial permanece obrigatória;
- SECURITY DEFINER preservado;
- RLS e empresa_id não foram relaxados;
- nenhuma empresa existente é alterada.

Validação pendente:
- aplicar corrigir_slug_nova_empresa_supabase_v1.sql no Supabase;
- criar uma empresa beta pelo APK;
- confirmar convite, licença e isolamento Empresa A x Empresa B.

---

## 2026-08-14 — Conciliação bancária segura V1

Módulo: Financeiro • Contas / Extrato bancário
Status: 🟢 Implementado localmente

Alterações:
- histórico de conciliações passa a permitir remover uma conciliação criada por engano;
- se a conciliação gerou um ajuste de saldo, a remoção apaga também o movimento de ajuste vinculado;
- remoção é executada em uma única transação SQLite;
- por segurança, o movimento só é removido se pertencer à mesma conta e tiver origem "Conciliação de conta";
- lançamentos bancários comuns não são apagados;
- saldo da conta volta a ser calculado a partir dos movimentos restantes;
- conciliação exige confirmação final antes de salvar;
- ação "Criar ajuste e conciliar" alerta que o ajuste altera o saldo financeiro;
- usuário pode escolher "Voltar e revisar" antes da confirmação.

Validação pendente:
- remover uma conciliação sem ajuste;
- remover uma conciliação com ajuste e conferir reversão do saldo;
- confirmar que lançamentos comuns permanecem intactos;
- validar confirmação em "Salvar conciliação", divergência e "Criar ajuste e conciliar";
- dart format, flutter analyze e flutter test.

---

## 2026-08-21 — Fechamento Fidelidade + 220h + Ponto + Clientes/Veículos/Agenda V3

Status geral: 🟡 Implementação concluída / validação de campo pendente

### 🛡️ Fidelidade por tempo
- temporariamente desativada sem apagar estrutura ou histórico;
- desconto manual continua disponível.

### 🟢 Regra mensal de 220 horas
- regra central criada;
- Ponto usa salário / 220;
- faltas e horas extras usam a mesma base;
- custos e precificação deixam de multiplicar 220 pela quantidade de funcionários;
- tela deixa de orientar 3 x 220 = 660.

### 🟢 Ponto/Funcionários
- ponto rápido confirmado;
- Realtime confirmado;
- offline/idempotência confirmados em código;
- diagnóstico e revogação confirmados;
- isolamento por empresa_id preservado;
- homologação física em dois aparelhos ainda pendente.

### 🟢 Clientes/Veículos/Agenda
- mapas, upload e download isolados por empresa_id confirmados em código;
- fila de exclusões e device_id confirmados.

### ⚠️ Veículo duplicado — correção V1
- cadastro rápido agora bloqueia segundo salvamento enquanto o primeiro está em andamento;
- VeiculoRepository compartilha a mesma Future em dois inserts concorrentes;
- placa repetida para o mesmo cliente reaproveita o cadastro existente;
- sync tenta reaproveitar veículo local pela placa antes de criar nova linha;
- permissões do funcionário não removem a separação por empresa_id.

Validação manual:
- tocar Salvar várias vezes e obter um único veículo;
- criar veículo pelo funcionário e confirmar um único veículo no administrador;
- validar Cliente/Veículo/Agenda entre Empresa 1 e Empresa 2.

---

## 2026-08-24 — Ajuste de testes legados para regra 220h V4

Status: 🟢 Implementado localmente

- regra de 220h mantida;
- testes financeiros antigos de 100h atualizados para 220h;
- custo de mão de obra/hora, custo fixo/hora, rateio fixo da OS, custo total e resultado da OS alinhados;
- texto residual "3 pessoas × 220h = 660h" removido;
- teste-fonte passou a exigir a mensagem correta de 220h.

---

## 2026-08-24 — BuildContext assíncrono do Ponto rápido V7

Status: 🟢 Implementado localmente

Correção:
- eliminado o aviso `use_build_context_synchronously` no Ponto rápido;
- V7 usa inserção direta no texto, sem coleção PowerShell de tamanho fixo;
- `if (!mounted)` fica antes do `showDialog` de confirmação;
- nenhuma regra de ponto, jornada, hora extra, sincronização ou empresa_id foi alterada.

Histórico:
- V5 não localizava o `showDialog` por depender de formatação exata;
- V6 localizou o diálogo, mas falhou ao tentar inserir linhas em coleção de tamanho fixo;
- V7 corrige somente a mecânica do patch.

---

## 2026-08-24 — Consulta automática de veículo por placa V2

Status: 🟡 Implementado localmente / backend externo pendente de configuração

Veículos:
- ao completar 7 caracteres da placa, o app consulta automaticamente;
- botão de lupa permite repetir a consulta;
- preenche marca, modelo, ano-modelo e cor;
- se a API falhar, cadastro manual continua disponível;
- consultas repetidas da mesma placa na mesma sessão usam cache;
- duas consultas simultâneas da mesma placa compartilham a mesma Future.

Segurança:
- token do provedor não fica no APK;
- Flutter chama somente a Edge Function `consultar-placa`;
- Edge Function exige usuário autenticado no Supabase;
- `FALCON_DATAHUB_TOKEN` fica somente nos Secrets do projeto;
- Edge Function devolve apenas placa, marca, modelo, ano e cor.

Veículo duplicado:
- proteção da tela confirmada;
- inserção idempotente confirmada;
- proteção do sync por placa confirmada;
- homologação física no APK ainda necessária.

Pendência para ativar:
- criar conta/token no provedor de placa;
- cadastrar secret `FALCON_DATAHUB_TOKEN`;
- publicar Edge Function `consultar-placa`.

---
## Modelo obrigatório para próximas entradas

```text
## AAAA-MM-DD — Nome da atualização

Módulo:
Status anterior:
Status novo:

Alterações:
- ...

Arquivos principais alterados:
- ...

Banco/migração:
- ...

Impacto na sincronização:
- nenhum / descrever

Impacto multiempresa:
- nenhum / descrever

Testes:
- flutter analyze:
- flutter test:
- teste manual:

Próximo passo:
- ...
```

## 2026-08-24 23:30:58 — Fechamento técnico das Etapas 1, 2 e 3 V1

### Resultado automatizado
- 🟢 **Etapa 1 — Ponto/Funcionários:** estrutura e marcadores críticos confirmados; regra de 220h confirmada; Realtime e validação da Etapa 1 presentes; lutter analyze e lutter test aprovados.
- 🟢 **Etapa 2 — Clientes/Veículos:** proteções contra duplicação confirmadas; consulta automática por placa presente; sincronização anti-duplicação confirmada; testes aprovados.
- 🟡 **Etapa 3 — Agenda:** estrutura localizada e aplicação/testes gerais aprovados; homologação prática multiaparelho/multiempresa ainda necessária.

### Homologação prática obrigatória antes de alterar para ✅
- Ponto/Funcionários: validar administrador × funcionário em dois aparelhos, offline → online, revogação de acesso e isolamento entre empresas.
- Clientes/Veículos: criar cliente/veículo em ambas as empresas e confirmar isolamento; criar veículo pelo funcionário e confirmar apenas um registro no funcionário e administrador.
- Agenda: criar, editar e excluir agendamento pelo administrador e funcionário; confirmar sincronização nos dois aparelhos; confirmar que Empresa 1 nunca visualiza Agenda da Empresa 2 e vice-versa.
- Consulta por placa: integração APK → Supabase Edge Function → Falcon validada em placa disponível no provedor.

> Regra do roadmap: este fechamento técnico não transforma automaticamente as etapas em ✅. O status ✅ só deve ser aplicado após as validações físicas acima.


## 2026-08-24 23:34:32 — Checkpoint seguro local checkpoint-20260824-233331

- 🛡️ **Checkpoint de segurança solicitado antes da revisão geral do app.**
- Branch local: $branch.
- dart format: aprovado.
- lutter analyze: aprovado.
- lutter test: aprovado.
- Nenhum push remoto executado por este checkpoint.
- O objetivo deste marco é preservar o estado funcional atual antes de revisar ajustes e iniciar novas alterações.
- Etapas 1/2/3 permanecem com seus estados de homologação registrados anteriormente; este checkpoint não altera automaticamente módulos para ✅.


## 2026-08-24 23:45:32 - Auditoria Financeiro Completo V3

- Status: EM REVISAO.
- Revisao integral do Financeiro iniciada antes da migracao cloud.
- Escopo: despesas, receitas/servicos, pagamentos, contas, fluxo de caixa, conciliacao bancaria, DRE, integracao com OS e capacidade de PDF.
- Relatorio tecnico criado: RELATORIO-AUDITORIA-FINANCEIRO-20260824-234422.md.
- flutter analyze: aprovado.
- flutter test: aprovado.
- Nenhuma regra financeira foi alterada nesta auditoria.
- Proximo passo: revisar o relatorio e corrigir o Financeiro por blocos, comecando pelas regras de competencia, caixa e origem unica dos movimentos.
- Requisito confirmado: DRE deve permitir geracao de PDF organizado e detalhado para conferencia.
## 2026-08-25 — Financeiro: DRE PDF e travas de regras V1

- 🟢 DRE PDF detalhado implementado localmente, com resumo executivo, contas/categorias e origens dos lançamentos.
- 🟢 Tela DRE recebeu ações para visualizar/imprimir e compartilhar o PDF do período e regime selecionados.
- 🛡️ Regra preservada: DRE por competência usa `data_competencia`.
- 🛡️ Regra preservada: DRE/fluxo por caixa usa `data_pagamento`.
- 🛡️ Regra preservada: previsão usa `data_vencimento`.
- 🛡️ Transferências permanecem fora do resultado do fluxo e da DRE.
- 🛡️ Conciliação permanece com `impacta_dre = 0`.
- 🛡️ A lógica atual de OS/recebimentos da DRE não foi reescrita; o PDF consome o `DreRepository` existente.
- 🟡 Validação pendente desta alteração: `flutter analyze`, teste específico e suíte completa.
- ⬜ Financeiro cloud permanece para a etapa oficial posterior da migração.

---

## 🟡 Financeiro — otimização completa local V1

Marcador: `financeiro-otimizacao-completa-v1`

- 🟢 Tela principal reorganizada em Faturamento, Recebido, A receber e Resultado do mês.
- 🟢 Valores financeiros ficam ocultos inicialmente e podem ser revelados pelo botão de olho.
- 🟢 Ações rápidas: Despesa, Receita, Receber OS e Transferir.
- 🟢 Quatro áreas principais: Movimentações, Contas, Fluxo de caixa e DRE.
- 🟢 Ferramentas secundárias agrupadas em Gestão e configurações financeiras.
- 🟢 Formulário manual unificado para receita/despesa com Realizado/Previsto e seção Mais detalhes.
- 🟢 Movimentações em lista compacta, mantendo movimentos automáticos protegidos pelo módulo de origem.
- 🟢 Fluxo de caixa reorganizado com saldo atual, saldo projetado, realizado e previsto.
- 🟢 `data_saldo_inicial` passa a funcionar como snapshot histórico da conta.
- 🟢 Snapshot ocorrido dentro do período passa a compor o saldo acumulado sem virar receita da DRE.
- 🟢 Desativar uma conta não reescreve o histórico global do fluxo de caixa.
- 🟢 Tabela `financeiro_conciliacoes_conta` formalizada no schema atual sem alterar `schemaVersion = 27`.
- 🛡️ Remoção segura da conciliação bancária preservada.
- 🛡️ DRE detalhada e PDF preservados.
- 🛡️ Pagamentos, parcelas, taxas, estornos, transferências e motor financeiro da OS não foram substituídos.
- 🟡 Migração do Financeiro para Supabase continua pendente; esta revisão é da camada local, regras e experiência de uso.
- ⬜ Homologar no APK: lançamento realizado, lançamento previsto, baixa, transferência, extrato, conciliação, fluxo, DRE e PDF.

## 2026-08-25 10:36:55 — Financeiro otimização V4 - teste robusto

- 🟢 inanceiro_regras_e_dre_pdf_source_test.dart reescrito de forma completa após a V3 ter feito uma alteração parcial.
- 🛡️ Nenhuma regra de negócio, saldo, banco, DRE, fluxo de caixa, pagamento ou OS foi alterada.
- 🛡️ O teste agora valida semanticamente: realizado = data de pagamento; previsto = vencimento/competência; transferências fora do fluxo operacional.
- 🛡️ Proteção da conciliação (impacta_dre = 0) e DRE PDF continuam verificadas.
- 🟡 Validação pendente: dart format, lutter analyze, teste específico e suíte completa.

---

## 2026-08-26 - Etapa 4: auditoria OS Cloud V2

Marcador: `os-cloud-auditoria-v2`

- 🟡 Auditoria local da Ordem de Servico iniciada antes da migracao cloud.
- 🛡️ Nenhuma regra, tabela SQLite ou tela foi alterada por esta auditoria.
- 🛡️ Financeiro permanece em homologacao de uso real e nao sera reescrito nesta etapa.
- 🟡 Supabase: schema da OS ainda nao criado; arquitetura sera definida apos revisao dos fontes ativos.
- ⬜ Proximo passo: desenhar schema cloud + RLS + mapeamento/sync idempotente da OS.



---

## 2026-08-27 - Etapa 4: OS Cloud upload-only V1

Marcador: os-cloud-upload-only-v1

- 🟢 Backend do nucleo da OS Cloud criado no Supabase com empresa_id e RLS.
- 🟢 Upload idempotente de ordens_servico e ordem_servico_itens integrado ao sync operacional.
- 🛡️ Nenhum download de OS para o SQLite nesta subetapa.
- 🛡️ Pagamentos e movimentos financeiros continuam locais.
- 🛡️ Produtos, lotes e movimentos de estoque continuam locais.
- 🛡️ Fotos e assinatura local nao sao enviadas como caminho de arquivo.
- 🛡️ Acesso remoto de funcionario a ordens_servico continua bloqueado.
- 🟡 Homologacao pendente: upload real, contagem e isolamento por empresa.
- ⬜ Proximo passo: checklist/revisoes e depois download controlado da OS.

---

## 2026-09-01 — Sprint 0 de estabilização do baseline

Módulo: Fundação / Qualidade / Git / Copilot / Consulta de placa
Status anterior: 🟡 baseline funcional com CI vermelho
Status novo: 🟢 validação local limpa; CI remoto aguardando confirmação

Alterações:
- warning `_data` removido;
- backups históricos removidos da árvore rastreada sem apagar histórico;
- instruções do Copilot criadas;
- fonte da Edge Function `consultar-placa` alinhada à V5 ativa, com contrato de teste preservado;
- roadmap e pendências atualizados.

Banco/migração:
- nenhuma alteração SQLite;
- nenhuma alteração de schema PostgreSQL;
- nenhum dado operacional apagado.

Testes:
- dart format: aprovado;
- flutter analyze: aprovado sem issues;
- teste de consulta de placa: aprovado;
- flutter test: aprovado;
- git diff --check: aprovado.

Próximo passo:
- homologar consulta de placa;
- homologar OS Cloud Upload-Only V1 com OS real.

---

## 2026-09-09 — Fiscal v31/v32 + CRM v1/v2 + revisão dos blocos comerciais

### Fiscal de entrada

🟡 **Consulta NFC-e assistida em validação real**
- QR/chave 44 dígitos e DV validados.
- XML NF-e/NFC-e continua como fonte estruturada preferencial quando disponível.
- Portal público oficial pode ser aberto dentro do Imperium; CAPTCHA é resolvido manualmente pelo usuário.
- Parser S@T/SEF-SC cobre o formato real homologado em cupom de mercado.
- Hotfix passa a detectar conteúdo fiscal em `iframe/frame/object/embed`, abrir o quadro oficial como página principal e repetir a importação.
- Edge Function autenticada `imperium-fiscal-dfe` permanece preparada para consulta estruturada de NF-e modelo 55 via provedor fiscal; credenciais nunca ficam no APK.

🟢 **Correção / exclusão segura de nota fiscal — implementação local v31**
- Nova auditoria `nota_fiscal_entrada_revisoes` preserva chave, número, emitente, motivo e detalhes.
- Nota sem integração pode ser excluída com motivo.
- Entrada de estoque ainda não consumida pode ser estornada transacionalmente.
- Lote já consumido por OS bloqueia desfazimento automático para proteger custo histórico/FIFO.
- Financeiro `Previsto` é cancelado sem mexer no saldo.
- Financeiro `Realizado` permanece no histórico como origem estornada, deixa de impactar DRE e recebe movimento compensatório de caixa; o saldo volta ao estado anterior sem apagar histórico.
- Depois da exclusão segura a mesma chave pode ser importada novamente.
- Tela fiscal recebe ação **Corrigir / excluir nota**.

### CRM

🟢 **CRM v1 — implementação local**
- Leads e pipeline: Novo contato, Qualificação, Orçamento, Aguardando cliente, Negociação, Agendado, Ganho e Perdido.
- Origem do lead, serviço/veículo de interesse, valor potencial, responsável, próximo contato e observações.
- Histórico de interações e mudança de etapa.
- Motivo obrigatório ao marcar oportunidade como perdida.
- Conversão de lead para cliente com anti-duplicação por telefone/e-mail.
- Vínculo de cliente e criação de agendamento quando cliente/veículo estiverem definidos.
- Indicadores: oportunidades abertas, valor do pipeline, follow-ups atrasados, ganhos/perdas e conversão mensal.
- Módulo `crm` incluído nas permissões; administrador recebe acesso padrão, funcionário continua restrito.

🟢 **CRM v2 — campanhas e benefícios, implementação local**
- Data de nascimento adicionada ao cadastro local de clientes.
- Campanhas: Aniversário, Reativação, Indicação e Manual.
- Benefícios: percentual, valor fixo, serviço ou crédito.
- Valor mínimo, validade e período sem retorno configuráveis.
- Geração idempotente de cupom de aniversário uma vez por cliente/ano/campanha.
- Geração idempotente de benefício de reativação por cliente/campanha/mês.
- Cupons com status Ativo, Usado, Expirado ou Cancelado e vínculo opcional à OS.
- Simulação de benefício informa quando o valor final fica abaixo do preço mínimo seguro.
- Automação externa de WhatsApp permanece futura; a v2 organiza e mede o benefício localmente.

### Precificação

✅ **Motor de precificação inteligente já existente — não duplicar**
- Custos fixos, mão de obra, regra das 220h, materiais, taxas, margem, preço mínimo seguro e preço sugerido já existem no módulo atual.
- CRM passa a poder comparar benefício/cupom com o preço mínimo seguro.
- Próxima evolução será experiência de simulação/integração comercial, não criação de um segundo motor de preço.

### Ordem de Serviço

✅ **Adicionar serviço em OS aberta/em andamento já implementado**
- `adicionarServicoCatalogoNaOrdem` trabalha em transação, valida produtos vinculados/estoque, adiciona itens e recalcula subtotal.
- Estoque continua sendo consumido na finalização conforme motor atual.
- Não criar fluxo paralelo para esta funcionalidade.

### Máquina de cartão

✅ **Regras avançadas já implementadas**
- Crédito/débito, parcelas 1x–12x, percentual/valor fixo, prazo de recebimento, repasse e conta da maquininha já fazem parte da estrutura atual.
- Próximas alterações devem ser refinamentos de UX/homologação, não um novo motor.

### Ponto / funcionários / login

🛡️ **Mantidos protegidos neste bloco**
- Estrutura existente permanece preservada para não arriscar autenticação, multiempresa e sincronização durante a expansão Fiscal/CRM.
- Avançar somente após homologação do APK desta etapa.

### Qualidade exigida antes do commit

- `dart format` nos arquivos alterados;
- `flutter analyze --no-pub` sem issues;
- testes focados Fiscal/CRM/schema/migrações;
- suíte completa;
- `git diff --check`;
- build `app-debug.apk`;
- teste real do mesmo cupom NFC-e no portal S@T/SEF-SC.


## Fiscal V33 — confiabilidade e reprocessamento
<!-- fiscal-v33-confiabilidade -->
- Rastreio de tentativas por canal (XML, QR direto, portal assistido, DF-e e manual).
- Reprocessamento idempotente da mesma chave sem duplicar documento.
- Validação forte do XML: chave, modelo, CNPJ, número, série, itens e totais.
- NFC-e com consulta pública + WebView assistido e diagnóstico copiável.
- Saúde Fiscal para reconciliar notas, itens, estoque e financeiro.
- Estoque e financeiro bloqueados para documento não autorizado.
- Backend DF-e v3 com sessão revalidada, CNPJ somente no servidor e sem manifestação automática.
---

## 2026-09-10 — Ranking de serviços pelo valor líquido

Módulo: Dashboard / Financeiro
Status anterior: 🟢 Implementado com divergência de valor / relatório duplicado
Status novo: ✅ Corrigido, consolidado e protegido por testes

Alterações:
- ranking de serviços deixou de somar o bruto dos itens isoladamente;
- valor líquido final da OS é distribuído proporcionalmente entre os serviços;
- desconto simples e desconto de negociação reduzem o ranking;
- acréscimo de negociação e juros de parcelamento seguem a mesma base usada pelo faturamento por competência;
- caso real de R$ 600 com R$ 250 de desconto passa a mostrar R$ 350;
- criado teste automatizado também cobrindo uma OS com múltiplos serviços;
- consolidada a tela de relatórios financeiros, removendo a cópia temporária `_corrigido` quando idêntica à oficial;
- criado teste-fonte garantindo que exista apenas a tela oficial de relatórios.

Arquivos principais alterados:
- lib/repositories/dashboard_repository.dart
- test/dashboard_ranking_servicos_liquido_test.dart
- lib/screens/relatorios_financeiros_page_corrigido.dart (removido quando idêntico)
- test/financeiro_relatorios_consolidacao_source_test.dart
- ROADMAP-IMPERIUM-MESTRE.md

Banco/migração:
- nenhuma alteração de schema;
- nenhum dado existente é regravado;
- correção é somente de consulta/relatório.

Impacto em sincronização/multiempresa:
- nenhum;
- não altera serviços protegidos, RLS, empresa_id, Auth ou sincronização.

Testes:
- dart format;
- flutter analyze;
- teste específico do ranking líquido;
- flutter test completo;
- git diff --check.

## 2026-09-11 - Sprint 1B - fluxo financeiro ponta a ponta

Status: ✅ validado localmente.

- teste integrado de OS com desconto e recebimento parcial;
- validacao de movimento financeiro e saldo da conta;
- validacao de Dashboard, ranking, DRE e Financeiro Dashboard;
- teste de parcelamento com taxa de cartao;
- teste de estorno com recomposicao do saldo a receber;
- DRE caixa passou a usar o mesmo contrato monetario da OS na alocacao de custo de produtos;
- schema permanece v33;
- nenhuma migration.

---
## 2026-09-11 - Diretriz multiplataforma oficial

Módulo: Arquitetura / Produto
Status novo: 🛡️ diretriz oficial registrada

Alterações:
- Android, Web e iOS passam a fazer parte do objetivo oficial do produto;
- mesma conta Supabase Auth entre plataformas;
- mesmo `empresa_id`, permissões e dados;
- cloud/multi-dispositivo deve ser consolidado antes da abertura Web/iOS;
- novas implementações devem preservar portabilidade Flutter;
- regras de negócio e repositories devem evitar dependências de plataforma.

Banco/migração:
- nenhuma.

Impacto na sincronização:
- define Supabase como fonte compartilhada entre plataformas para módulos migrados;
- reforça idempotência, conflitos, RLS e identidade global.

Impacto multiempresa:
- mantém isolamento obrigatório por `empresa_id`.

Próximo passo:
- concluir homologação Financeiro no Android;
- seguir homologações multi-dispositivo;
- continuar migração cloud na ordem oficial.


## 2026-09-11 - Estoque Cloud Upload-Only V1

Módulo: Estoque / Sincronização
Status anterior: 🟢 estoque local avançado; cloud pendente
Status novo: 🟡 upload-only V1 preparado; homologação real pendente

Alterações:
- tabelas remotas de itens, lotes e movimentações criadas no Supabase;
- isolamento por `empresa_id` e RLS usando permissão do módulo `estoque`;
- identidade remota idempotente por dispositivo + ID local;
- itens e lotes podem ser atualizados/soft-deletados;
- movimentações são append-only para o app: INSERT/SELECT, sem UPDATE/DELETE;
- `EstoqueCloudUploadService` publica na ordem item → lote → movimentação;
- relação com OS usa o UUID remoto já mapeado quando existir;
- usuário sem permissão de Estoque não bloqueia os outros módulos do sync;
- nenhuma rotina de download de estoque foi ativada nesta V1.

Banco/migração:
- SQLite continua v33, sem migration local;
- Supabase migration `20260912023332_estoque_cloud_upload_v1`.

Próximo passo:
- download controlado/reconciliação do Estoque;
- homologação posterior em dois dispositivos.


## 2026-09-11 - Estoque Cloud Download Controlado V2

Módulo: Estoque / Sincronização
Status anterior: 🟡 upload-only V1
Status novo: 🟡 download de novos registros implementado; conflitos V2.1 pendentes

Alterações:
- itens novos da mesma empresa podem ser importados para outro dispositivo;
- lotes novos são importados após o item correspondente;
- movimentações novas são importadas como histórico append-only;
- movimentação baixada não reaplica saldo sobre o snapshot do item;
- mapas locais são reconstruídos quando a origem é o próprio dispositivo e houve interrupção antes de salvar o mapa;
- registros remotos já mapeados não sobrescrevem a versão local nesta etapa;
- download do estoque ocorre depois do download da OS para aproveitar vínculos já disponíveis.

Segurança:
- RLS existente do Estoque V1 continua protegendo por `empresa_id`;
- usuário sem permissão de Estoque não interrompe a sincronização dos demais módulos.

Banco/migração:
- nenhuma migration SQLite;
- schema local continua v33;
- nenhuma nova migration Supabase nesta etapa.

Próximo passo:
- V2.1: versão/conflitos e atualização segura de itens/lotes já mapeados;
- depois reserva/consumo compartilhado por OS.


## 2026-09-11 - Estoque Cloud Conflitos V2.1

Status: 🟡 proteção contra concorrência implementada; resolução V2.2 pendente.

Regra:
- só local mudou: upload pode seguir;
- só nuvem mudou: aplica versão remota localmente;
- local e nuvem mudaram: registra conflito e não sobrescreve;
- conflito pendente bloqueia upload do item/lote;
- movimentações seguem append-only.

Infraestrutura:
- `imperium_sync_estoque_conflitos` guarda snapshots e metadados;
- reconciliação ocorre antes do upload;
- SQLite de domínio continua v33;
- nenhuma migration Supabase nova.
