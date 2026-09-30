# Pendências técnicas

Última atualização: **2026-09-30**

> Este arquivo registra somente pendências técnicas ainda abertas.
> O histórico completo das etapas concluídas permanece no
> `ROADMAP-IMPERIUM-MESTRE.md`.

## Estado consolidado

As dívidas antigas de Cloud/Web registradas neste arquivo foram implementadas
nas etapas posteriores do roadmap:

- Estoque Cloud + CAS/reservas/FIFO/Realtime;
- Financeiro Cloud + estorno/transferência/conciliação;
- Precificação Cloud + CAS + admin-only;
- Configurações Cloud;
- CRM/Orçamentos Cloud;
- Arquivos/Storage da OS;
- isolamento SQLite multiempresa;
- motor unificado de sincronização;
- Web Foundation e paridade App → Web;
- OS Web transacional;
- reestilização profissional Web.

## Pendências que exigem homologação física

- Ponto com funcionário autenticado em segundo aparelho;
- offline → online com interrupção real de rede e confirmação de idempotência;
- Empresa A × Empresa B usando contas/tenants reais;
- concorrência real entre dois aparelhos nas operações críticas;
- consulta de placa em cenário real;
- homologação completa do APK de produção;
- iOS em dispositivo Apple depois do build sem assinatura no CI.

## iOS

Status: 🟡 bootstrap e gate de CI em implantação.

- scaffold oficial gerado por `flutter create --platforms=ios` em runner macOS;
- identificador base `br.com.imperiumdetailing`;
- build CI: `flutter build ios --release --no-codesign`;
- assinatura, provisioning profile e publicação exigem conta Apple Developer e
  não podem ser homologados apenas por CI sem credenciais Apple.

## Segurança / Supabase

Status: 🟡 hardening contínuo.

Concluído em 2026-09-30:
- teste automatizado contra segredos de servidor versionados;
- auditoria de Advisors;
- policy do Ponto otimizada para evitar reavaliação de `auth.uid()`;
- índice duplicado de OS removido preservando a constraint;
- índices de FKs críticas do Ponto adicionados;
- migration `20260930203129_roadmap_hardening_ponto_indices_rls` aplicada.

Advisors ainda podem reportar:
- tabelas internas com RLS e sem policy: comportamento intencional deny-by-default,
  com acesso por RPC controlada;
- RPCs `SECURITY DEFINER` acessíveis a `authenticated`: necessárias para
  operações transacionais/privilegiadas e protegidas por guardas internas;
- índices ainda não utilizados: informativo enquanto o volume de produção é baixo;
- proteção de senha vazada: configuração do Supabase Auth, dependente da
  configuração/plano do projeto.

## Qualidade

Obrigatório antes de considerar um HEAD homologável:
- `dart format` sem diff;
- `flutter analyze`;
- `flutter test`;
- Web Preview Build;
- Android APK Build;
- Mobile APK Build quando aplicável;
- iOS Build sem assinatura após o scaffold existir;
- migrations versionadas no repositório e aplicadas no Supabase.

## Regra de encerramento

Não marcar homologações físicas como concluídas por inferência. Elas só fecham
quando executadas com aparelhos/contas reais e resultado registrado no roadmap.
