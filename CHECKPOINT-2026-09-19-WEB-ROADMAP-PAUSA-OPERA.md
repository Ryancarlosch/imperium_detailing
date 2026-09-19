# CHECKPOINT — WEB ROADMAP PAUSADO — 2026-09-19

## Motivo da pausa

Pausa solicitada para atualização do Opera. Retomar exatamente deste ponto.

## Branch oficial

- `desenvolvimento`
- HEAD após autoformat: `b610426a6b49612068746554da3901247f25af1a`

## Direção aprovada do produto

- Prioridade atual: desenvolver o Web inteiro módulo por módulo.
- Mobile continua compartilhando backend/regras quando aplicável.
- Web deve ter acabamento profissional de SaaS/ERP, não aparência de app mobile esticado.
- Nome Imperium continua provisório; rebranding futuro deve ser simples.
- CRM, Pós-venda e Marketing ficam separados:
  - CRM = aquisição.
  - Pós-venda = retenção/retorno/reativação.
  - Marketing = conteúdo, campanhas, atribuição e métricas.

## Concluído nesta sessão antes da pausa

### Workspace Web

- Login direciona diretamente para o workspace completo.
- Dashboard intermediário removido.
- Sidebar principal preservada.
- Plano e assinatura preservados no menu da conta.

### Clientes Web

- Cabeçalho profissional.
- Resumo da carteira.
- Busca por nome, telefone, e-mail e endereço.
- Filtro de arquivados.
- Tabela desktop.
- Cards responsivos.
- Editar / arquivar / reativar.

### Pós-venda

- Módulo separado do CRM.
- Regras configuráveis de retorno e reativação.
- Status automáticos com base no histórico:
  - Em dia.
  - Hora do retorno.
  - Reativação.
  - Agendado.
- Registro de contatos.
- Próximo contato.
- Histórico de interações.

### Marketing

- Módulo separado.
- Campanhas.
- Investimento, alcance, cliques e leads.
- Atribuição de OS finalizada à campanha.
- Faturamento atribuído.
- ROAS geral.
- Desempenho por campanha.
- Agenda de conteúdo:
  - Post.
  - Reel.
  - Story.
  - Carrossel.
  - Plataforma.
  - legenda/roteiro.
  - campanha relacionada.
  - status.
  - data planejada.
- Integração Meta real ainda futura; estrutura já preparada.

### Veículos Web

- Redesign profissional concluído.
- Busca.
- Resumo.
- Tabela desktop.
- Cards responsivos.
- Vínculo claro com cliente.
- Formulário melhorado.
- Observações.
- Confirmação de exclusão.

### Agenda Web

- Redesign profissional concluído.
- Criação e edição real.
- Seleção de data via DatePicker.
- Seleção de hora via TimePicker.
- Status.
- Observações.
- Busca.
- Filtros:
  - Todos.
  - Abertos.
  - Concluídos.
  - Cancelados.
- Indicadores:
  - Hoje.
  - Próximos.
  - Em aberto.
  - Valor previsto.
- Tabela desktop.
- Cards responsivos.
- Confirmação de exclusão.

## Estado de validação no momento da pausa

- O preview anterior falhou apenas no check de formatação.
- `Dart Auto Format` concluiu com sucesso.
- O bot gerou o commit `b610426a` com o `dart format`.
- Flutter Quality e Mobile APK Build ainda estavam em execução quando a pausa foi solicitada.
- Não iniciar novo módulo antes de consultar o CI deste HEAD.

## Próxima tarefa EXATA

### 1. Conferir CI do HEAD `b610426a`

Confirmar:
- Dart format.
- Flutter analyze.
- Flutter test.
- Web build.
- APK build.

Corrigir antes de avançar se houver falha real.

### 2. Próximo módulo: Ordens de Serviço Web

Profissionalizar a tela de OS existente, preservando regras de negócio.

Objetivos:
- cabeçalho gerencial;
- resumo de OS abertas/em andamento/finalizadas;
- busca;
- filtros por status/pagamento/período;
- tabela desktop;
- cards responsivos;
- cliente + veículo + valores;
- valor negociado;
- recebido;
- pendente;
- acesso às ações existentes;
- integrar com telas Web de criação, arquivos, finalização e cancelamento já existentes;
- não duplicar lógica já implementada.

### 3. Depois de OS, seguir nesta ordem

1. Financeiro.
2. Estoque.
3. CRM.
4. Pós-venda refinamento Web.
5. Marketing refinamento Web.
6. Orçamentos.
7. Precificação.
8. Equipe / Ponto.
9. Administração / Cloud / Configurações.
10. Dashboard gerencial final.
11. Padronização visual global.
12. Revisão completa de responsividade, loading, empty states e erros.
13. Gate final do roadmap Web.

## Regra de retomada

Ao voltar, ler este checkpoint primeiro e continuar em **Ordens de Serviço Web** após validar o CI.
