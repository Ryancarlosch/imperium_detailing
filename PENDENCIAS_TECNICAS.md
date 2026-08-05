# Pendências técnicas

## Flutter Analyze

- Atualizar `DropdownButtonFormField` de `value` para `initialValue`.
- Substituir `withOpacity` por `withValues`.
- Revisar widgets não utilizados no dashboard.
- Corrigir underscores desnecessários.
- Revisar uso de elementos null-aware.

## Regras

- Nenhuma nova funcionalidade deve aumentar a quantidade de erros ou warnings.
- Antes de cada commit, executar `flutter analyze`.
- Antes de cada commit, executar `flutter test`.
- Corrigir avisos do arquivo sempre que ele for alterado.
- Não aplicar correções automáticas em massa sem revisão.

## Estado atual

- Aplicativo abrindo no emulador.
- Testes atuais passando.
- Issues restantes: 30.