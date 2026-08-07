# CHECKLIST DE RELEASE — IMPERIUM DETAILING

Use este checklist sempre que for gerar um APK que substituirá uma versão instalada.

## 1. Código

- [ ] Confirmar branch correta.
- [ ] Executar `git status`.
- [ ] Confirmar que não existem arquivos inesperados.
- [ ] Confirmar que alterações importantes foram commitadas.
- [ ] Executar `git pull` quando necessário e resolver conflitos antes de gerar o APK.

## 2. Qualidade

Executar:

```powershell
.\scripts\validar_projeto.ps1
```

Obrigatório:

- [ ] `dart format` sem diferenças.
- [ ] `flutter analyze` → `No issues found!`.
- [ ] `flutter test` → `All tests passed!`.
- [ ] `git diff --check` sem erros.
- [ ] GitHub Actions verde no commit da versão.

Não gerar versão para uso real se algum item obrigatório falhar.

## 3. Backup antes da atualização

No celular que receberá a atualização:

- [ ] Abrir a versão atualmente instalada.
- [ ] Criar backup.
- [ ] Compartilhar o ZIP para computador ou nuvem.
- [ ] Confirmar que o arquivo externo existe.
- [ ] Não deixar a única cópia dentro da pasta do aplicativo.

## 4. Versão

Conferir `pubspec.yaml`.

Formato:

```yaml
version: MAJOR.MINOR.PATCH+BUILD
```

Exemplo:

```yaml
version: 1.0.1+2
```

Regras:

- [ ] Aumentar `BUILD` a cada APK distribuído.
- [ ] Aumentar `PATCH` para correções.
- [ ] Aumentar `MINOR` para conjuntos relevantes de funcionalidades.
- [ ] Aumentar `MAJOR` somente para mudança grande/incompatível.

Depois:

```powershell
flutter pub get
```

## 5. Assinatura e tipo do APK

### APK de teste/debug

Use apenas para atualização de uma instalação que também foi criada com a mesma chave debug da mesma máquina.

```powershell
flutter build apk --debug
```

Arquivo esperado:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

### APK de produção/release

Somente usar quando a assinatura release estiver configurada e preservada.

```powershell
flutter build apk --release
```

Arquivo esperado:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Antes de distribuir release:

- [ ] Confirmar chave de assinatura correta.
- [ ] Confirmar que a chave está armazenada com segurança.
- [ ] Confirmar que a senha não foi commitada no Git.
- [ ] Confirmar que o APK anterior de produção usa a mesma assinatura.

## 6. Instalação como atualização

No Android:

- [ ] Abrir o novo APK.
- [ ] O sistema deve oferecer **Atualizar**.
- [ ] Não continuar se o Android exigir desinstalação do aplicativo atual.
- [ ] Não usar `Limpar dados`.
- [ ] Não desinstalar a versão existente para "resolver" conflito de assinatura.

Se a atualização não for aceita, investigar:

- `applicationId`;
- assinatura;
- `versionCode`;
- variante debug/release.

Não apagar os dados para contornar o problema.

## 7. Smoke test imediatamente após instalar

- [ ] Aplicativo abre.
- [ ] Dashboard abre.
- [ ] Cliente antigo existe.
- [ ] Veículo antigo existe.
- [ ] OS antiga existe.
- [ ] Foto antiga abre.
- [ ] Assinatura antiga abre.
- [ ] Estoque foi preservado.
- [ ] Financeiro foi preservado.
- [ ] Fechar e reabrir o aplicativo.
- [ ] Dados continuam presentes.

## 8. Teste funcional

Executar o arquivo:

```text
TESTE_MANUAL.md
```

Para versões internas pequenas, pelo menos os fluxos críticos devem ser executados.

Para versão considerada estável/distribuível, executar o roteiro completo.

## 9. Backup pós-atualização

Depois de aprovar a atualização:

- [ ] Criar novo backup usando a versão instalada.
- [ ] Salvar externamente.
- [ ] Identificar o backup com versão e data.

Exemplo:

```text
Imperium_1.0.1_build2_2026-08-06.zip
```

## 10. Git

Depois da validação:

```powershell
git status
git add .
git commit -m "release: preparar versao X.Y.Z"
git push origin desenvolvimento
```

Quando apropriado para o processo do projeto, criar tag:

```powershell
git tag -a vX.Y.Z -m "Imperium Detailing vX.Y.Z"
git push origin vX.Y.Z
```

Não criar tag de release para uma versão que ainda não passou pelo teste manual.

## 11. Registro da versão

Preencher antes de considerar o release encerrado:

```text
Versão:
Build:
Data:
Commit:
Tipo de APK: debug / release
Dispositivo testado:
Android:
Backup anterior salvo: sim / não
Backup posterior salvo: sim / não
Validação automática: passou / falhou
Teste manual: passou / falhou
Observações:
```

## 12. Critérios para bloquear publicação

Não publicar/instalar como versão principal quando houver:

- perda de dados;
- falha de migração;
- banco corrompido;
- fotos ou assinaturas desaparecendo;
- lançamento financeiro duplicado;
- estoque negativo;
- baixa parcial após falha;
- OS mudando de estado incorretamente;
- backup que não pode ser restaurado;
- `flutter analyze` com issues;
- testes automatizados falhando;
- tela vermelha ou crash em fluxo principal.

## 13. Aprovação

Somente marcar como aprovada quando:

- [ ] validação automática passou;
- [ ] GitHub Actions passou;
- [ ] backup anterior foi salvo;
- [ ] atualização ocorreu sem desinstalação;
- [ ] dados antigos foram preservados;
- [ ] smoke test passou;
- [ ] testes manuais críticos passaram;
- [ ] backup pós-atualização foi criado;
- [ ] commit da versão está no Git.
