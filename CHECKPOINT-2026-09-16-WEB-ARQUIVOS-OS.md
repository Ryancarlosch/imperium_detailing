# Checkpoint Imperium — Arquivos da OS no Web

Data: 2026-09-16
Branch: `desenvolvimento`

## Objetivo deste lote

Levar para o Web a leitura dos arquivos de Ordem de Serviço que já são sincronizados pelo Android, reutilizando a infraestrutura existente do Supabase Storage e sem criar banco ou fluxo paralelo.

## Implementado

### Serviço Web de arquivos da OS

Arquivo: `lib/services/web_os_arquivos_service.dart`

- usa a empresa ativa da sessão;
- consulta a OS por `empresa_id`;
- consulta `imperium_ordem_servico_fotos`;
- consulta `imperium_ordem_servico_checklist` para fotos de avaria;
- lê a assinatura já vinculada em `imperium_ordens_servico`;
- respeita soft delete (`excluido_em`);
- reutiliza o bucket privado `imperium-os-arquivos`;
- baixa conteúdo com Supabase Storage como bytes (`Uint8List`);
- não depende de `dart:io`;
- não cria URL pública para o bucket privado.

### Visualizador Web

Arquivo: `lib/web/web_os_arquivos_page.dart`

- mostra totais de fotos, avarias e existência de assinatura;
- lista os arquivos sincronizados;
- abre a imagem diretamente de bytes;
- permite zoom com `InteractiveViewer`;
- possui atualização manual;
- mantém o Storage privado.

### Integração na lista de Ordens de Serviço

Arquivo: `lib/web/web_ordens_v3_page.dart`

- adiciona botão `Fotos, avarias e assinatura` em cada OS;
- abre `WebOsArquivosPage` usando o ID e número da OS;
- mantém intacta a regra de edição apenas para OS `Aberta` ou `Em andamento`.

### Teste de contrato

Arquivo: `test/web_os_arquivos_source_test.dart`

Protege:

- filtros por `empresa_id` e `ordem_servico_id`;
- soft delete;
- tabelas remotas corretas;
- bucket privado correto;
- download por bytes;
- ausência de `createPublicUrl`;
- ausência de `dart:io` na implementação Web;
- integração do botão da lista de OS com `WebOsArquivosPage`;
- preservação da restrição de edição por status.

## Commits do lote

- `9dc37d5` — `feat(web): adiciona leitura dos arquivos da OS`
- `47814ee` — `feat(web): adiciona visualizador de arquivos da OS`
- `c9926cb` — `test(web): protege visualizacao dos arquivos da OS`
- `f01e3bd` — `style: aplica dart format`
- `503037f` — `docs: registra checkpoint dos arquivos da OS web`
- `39bbbe2` — `test(web): reforca isolamento dos arquivos da OS`
- `32b76ed` — `feat(web): liga arquivos a lista de OS`
- `768f22c` — `test(web): protege acesso aos arquivos pela OS`
- `fea671b` — `style: aplica dart format`

## Validação confirmada em 2026-09-16

No computador de desenvolvimento, já alinhado ao commit `fea671b`:

- `flutter test test/web_os_arquivos_source_test.dart` — PASSOU;
- `flutter analyze` — PASSOU (`No issues found`);
- `flutter build web --target lib/main_web_bootstrap.dart --release` — PASSOU (`Built build\\web`).

O build exibiu apenas avisos não bloqueantes:

- dry run de WebAssembly apontando incompatibilidades no pacote `image 4.3.0`;
- aviso de fonte `CupertinoIcons` não encontrada durante tree-shaking.

Esses avisos não impediram a compilação Web atual e ficam registrados para tratamento futuro caso o projeto passe a exigir build WASM ou uso efetivo dessa fonte.

## Regra de segurança preservada

Nenhuma alteração deste lote mexe em:

- finalização transacional da OS;
- baixa de estoque;
- financeiro;
- autenticação;
- licença;
- RLS;
- sincronização Android existente.

O Web apenas lê arquivos já sincronizados e autorizados pelas políticas existentes da empresa.

## Evolução V2 — 2026-09-19

O fluxo deixou de ser somente leitura. O Web agora também envia fotos, cria/edita checklist e avarias e captura assinatura, sempre no bucket privado, com isolamento por empresa, origem idempotente e proteção concorrente por `atualizado_em`.

OS finalizada ou cancelada permanece somente para consulta.

## Estado do lote

✅ **Arquivos da OS Web V2 — leitura e escrita implementadas.**

A lista Web de Ordens de Serviço permite acessar e, enquanto a OS estiver editável, registrar fotos, avarias, checklist e assinatura sincronizados, respeitando `empresa_id`, concorrência, soft delete e Storage privado.

## Próximo passo exato

1. atualizar o roadmap mestre com a conclusão de `Arquivos da OS Web V1`;
2. manter este lote congelado salvo correção identificada em homologação;
3. continuar a próxima etapa do desenvolvimento Web conforme prioridade do roadmap.
