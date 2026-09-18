# Preparação iOS — Imperium Manager

Data de referência: 2026-09-18

## Estado atual

O repositório ainda não possui a pasta `ios/` versionada.
A arquitetura Flutter compartilhada já está sendo preparada para Android, Web e iOS.
A estrutura nativa iOS deve ser gerada pelo Flutter em um Mac com Xcode.

## Antes de gerar a plataforma

- usar a mesma branch `desenvolvimento`;
- garantir árvore Git limpa;
- usar Flutter estável compatível com o projeto;
- rodar `flutter pub get`;
- confirmar que `flutter analyze` e `flutter test` passam.

## Gerar a base iOS no Mac

No diretório raiz do projeto:

```bash
bash scripts/preparar_ios_macos.sh SEU_BUNDLE_IDENTIFIER
```

Exemplo de formato:
```text
br.com.suaempresa.imperiummanager
```

Esse script:
- exige Mac;
- exige árvore Git limpa;
- gera a pasta `ios/` pelo Flutter;
- aplica automaticamente nome do app, permissões de câmera/fotos e URL scheme;
- aplica o Bundle Identifier informado no projeto Xcode;
- não sobrescreve uma pasta `ios/` já existente.

Depois, versionar a pasta `ios/` gerada e revisar o diff antes de qualquer build assinada.

## Contratos nativos obrigatórios

### Nome

Display name:
- Imperium Manager

### Deep links

Contrato Dart:
- arquivo: `lib/config/imperium_app_links.dart`
- scheme: `imperiumdetailing`
- login: `imperiumdetailing://login-callback/`
- pagamento: `imperiumdetailing://payment-return/`

No iOS, registrar o scheme `imperiumdetailing` em `CFBundleURLTypes`.
O script `scripts/configurar_ios_imperium.py` faz essa configuração automaticamente.
Não criar outro scheme exclusivo para iOS.

### Privacidade — câmera e fotos

O app usa `image_picker` e câmera/fotos em OS, checklist, galeria e configurações.

Adicionar em `ios/Runner/Info.plist`:

- `NSCameraUsageDescription`
  - "O Imperium usa a câmera para registrar veículos, serviços, checklist e documentos."
- `NSPhotoLibraryUsageDescription`
  - "O Imperium acessa suas fotos para anexar imagens de veículos, serviços e documentos."
- `NSPhotoLibraryAddUsageDescription`
  - "O Imperium pode salvar imagens e documentos gerados pelo aplicativo."

O app não grava vídeo como funcionalidade atual; não adicionar permissão de microfone sem necessidade real.

### Notificações

`NotificationService` já possui implementação Darwin/iOS.
A permissão é solicitada em runtime pelo plugin e não deve ser pedida silenciosamente na inicialização.

Homologar em aparelho físico:
- permissão;
- lembrete de agendamento;
- lembrete diário do CRM;
- cancelamento/reagendamento.

### Supabase Auth

O iOS deve usar a mesma conta Supabase e a mesma empresa do Android/Web.
Homologar:
- cadastro;
- confirmação;
- login por e-mail/senha;
- recuperação/magic link quando aplicável;
- callback `imperiumdetailing://login-callback/`;
- restauração de sessão;
- funcionário revogado em Realtime.

### SQLite e offline

O mobile iOS deve seguir a mesma arquitetura do Android:
- SQLite local por empresa;
- Cloud como referência compartilhada;
- cache/offline local;
- fila/retry;
- conflitos explícitos;
- isolamento Empresa A × Empresa B.

### Arquivos e Storage

Homologar em iPhone:
- fotos;
- checklist;
- assinatura;
- comprovantes financeiros;
- PDF;
- compartilhamento;
- download/upload privado no Supabase Storage.

### Google Drive

O backup Google Drive usa `google_sign_in`.
Antes de considerar paridade iOS concluída, configurar o cliente OAuth iOS correspondente e o URL scheme exigido pelo Google Sign-In.
Não publicar o app assumindo que a configuração Android serve automaticamente no iOS.

## Bundle Identifier e assinatura

Não publicar com `com.example` nem com identificador temporário.
Definir o Bundle Identifier definitivo antes do primeiro envio ao App Store Connect/TestFlight.

O script de bootstrap exige esse identificador explicitamente e não assume um valor definitivo.
O identificador final deve ser confirmado pelo proprietário da conta Apple antes do primeiro upload.

## Gate no Mac

Executar, nesta ordem:

```bash
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
```

Depois da compilação sem assinatura:
- abrir o projeto iOS no Xcode;
- configurar Team;
- configurar Bundle Identifier definitivo;
- revisar Signing & Capabilities;
- executar em iPhone físico;
- só então preparar Archive/TestFlight.

## Homologação mínima no iPhone

- login administrador;
- login funcionário e permissões;
- cliente/veículo;
- agenda;
- OS completa;
- fotos/checklist/assinatura;
- estoque;
- financeiro;
- CRM/orçamentos;
- precificação/configurações;
- ponto;
- offline -> online;
- conflito entre dois dispositivos;
- Empresa A × Empresa B;
- licença vencida/revogação;
- notificações;
- PDF/compartilhamento;
- backup/recovery aplicável.

## Regra de fechamento

iOS só é considerado pronto quando a mesma matriz crítica do Android/Web passar em um iPhone físico e a build distribuída pelo TestFlight for validada.
