# TESTE MANUAL — IMPERIUM DETAILING

Este roteiro deve ser usado antes de gerar uma versão que será instalada no celular principal ou entregue para uso real.

## 1. Preparação

- [ ] Executar `.\scripts\validar_projeto.ps1`.
- [ ] Confirmar `No issues found!`.
- [ ] Confirmar `All tests passed!`.
- [ ] Confirmar `VALIDACAO CONCLUIDA COM SUCESSO.`.
- [ ] Confirmar `git status`.
- [ ] Confirmar que não existem alterações inesperadas no Git.
- [ ] Criar um backup externo do aplicativo atual.
- [ ] Salvar o backup fora da pasta do aplicativo, preferencialmente no computador ou nuvem.

## 2. Atualização do APK

- [ ] Instalar o novo APK usando a opção **Atualizar**.
- [ ] Não desinstalar o aplicativo anterior.
- [ ] Não usar **Limpar dados**.
- [ ] Confirmar que o aplicativo abre sem erro.
- [ ] Fechar completamente o aplicativo.
- [ ] Abrir novamente.
- [ ] Confirmar que os dados continuam disponíveis.

## 3. Dados antigos

Conferir pelo menos um registro real já existente antes da atualização.

- [ ] Cliente antigo continua cadastrado.
- [ ] Veículo continua vinculado ao cliente correto.
- [ ] Ordem de Serviço antiga abre normalmente.
- [ ] Status da OS foi preservado.
- [ ] Valores da OS foram preservados.
- [ ] Checklist antigo foi preservado.
- [ ] Fotos antigas foram preservadas.
- [ ] Assinatura do cliente foi preservada.
- [ ] Estoque continua com os saldos esperados.
- [ ] Financeiro continua exibindo os movimentos anteriores.

## 4. Clientes

Criar um cliente identificado como teste.

Exemplo: `Cliente Teste Atualização`.

- [ ] Cadastrar cliente.
- [ ] Editar telefone ou observação.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar persistência.
- [ ] Arquivar cliente.
- [ ] Confirmar que saiu da lista de ativos.
- [ ] Abrir lista/filtro de arquivados.
- [ ] Confirmar que aparece como arquivado.
- [ ] Confirmar que veículos e histórico não foram apagados.
- [ ] Reativar cliente.
- [ ] Confirmar retorno para a lista de ativos.

## 5. Veículos

- [ ] Cadastrar veículo para o cliente de teste.
- [ ] Confirmar vínculo com o cliente.
- [ ] Editar informação do veículo.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar persistência.
- [ ] Abrir histórico do veículo.

## 6. Agenda e orçamento

- [ ] Criar agendamento de teste.
- [ ] Editar agendamento.
- [ ] Criar orçamento.
- [ ] Adicionar itens ao orçamento.
- [ ] Confirmar valores.
- [ ] Converter o fluxo para Ordem de Serviço, quando aplicável.
- [ ] Confirmar que vínculos anteriores continuam corretos.

## 7. Ordem de Serviço

Criar uma OS de teste.

- [ ] OS inicia como aberta.
- [ ] Dados do cliente estão corretos.
- [ ] Dados do veículo estão corretos.
- [ ] Serviços estão corretos.
- [ ] Valor total está correto.
- [ ] Desconto está correto.
- [ ] Alterar para `Em andamento`.
- [ ] Confirmar data/hora de início.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar persistência.

## 8. Checklist

Durante a OS de teste:

- [ ] Abrir checklist.
- [ ] Confirmar itens padrão.
- [ ] Marcar item como OK.
- [ ] Registrar uma avaria.
- [ ] Adicionar observação.
- [ ] Informar localização da avaria.
- [ ] Adicionar foto da avaria.
- [ ] Informar quilometragem.
- [ ] Informar combustível.
- [ ] Salvar.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar persistência.

## 9. Fotos da OS

- [ ] Adicionar foto em `Antes`.
- [ ] Adicionar segunda foto em `Antes`.
- [ ] Adicionar foto em `Depois`.
- [ ] Confirmar separação correta entre etapas.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar que todas permanecem acessíveis.

## 10. Assinatura

- [ ] Registrar assinatura do cliente.
- [ ] Fechar e abrir a OS.
- [ ] Confirmar que a assinatura permanece disponível.

## 11. Finalização da OS

Antes deste teste, use valores e produtos claramente identificados como teste.

- [ ] Colocar a OS em andamento.
- [ ] Confirmar estoque suficiente para os produtos da OS.
- [ ] Finalizar a OS.
- [ ] Informar forma de pagamento.
- [ ] Confirmar status `Finalizada`.
- [ ] Confirmar data de finalização.
- [ ] Confirmar hora de saída.
- [ ] Confirmar valor final considerando desconto.
- [ ] Confirmar lançamento financeiro.
- [ ] Confirmar que existe somente um lançamento referente à OS.
- [ ] Confirmar baixa dos produtos do estoque.
- [ ] Confirmar movimentações de estoque.
- [ ] Confirmar consumo FIFO dos lotes quando houver mais de um lote.

## 12. Correção de OS finalizada

Usar a OS de teste finalizada.

- [ ] Abrir `Corrigir OS`.
- [ ] Tentar salvar motivo com menos de 5 caracteres.
- [ ] Confirmar que o aplicativo impede.
- [ ] Informar motivo válido.
- [ ] Alterar observação, responsável, quilometragem ou horário.
- [ ] Salvar.
- [ ] Confirmar que continua `Finalizada`.
- [ ] Confirmar alteração dos dados.
- [ ] Confirmar incremento da revisão.
- [ ] Confirmar registro do motivo.
- [ ] Se havia assinatura, confirmar indicação de assinatura desatualizada.
- [ ] Tentar salvar novamente sem mudar nenhum campo.
- [ ] Confirmar que revisão vazia é recusada.

## 13. Correção de checklist finalizado

- [ ] Abrir checklist da OS finalizada.
- [ ] Informar motivo da correção.
- [ ] Alterar um item.
- [ ] Alterar quilometragem ou combustível.
- [ ] Salvar.
- [ ] Confirmar nova revisão.
- [ ] Fechar e abrir novamente.
- [ ] Confirmar persistência.
- [ ] Confirmar que a OS continua finalizada.

## 14. Correção de fotos da OS finalizada

- [ ] Informar motivo.
- [ ] Adicionar foto `Antes`.
- [ ] Confirmar registro da revisão.
- [ ] Adicionar foto `Depois`.
- [ ] Confirmar registro da revisão.
- [ ] Excluir somente uma foto criada para teste.
- [ ] Confirmar que as demais fotos não foram apagadas.
- [ ] Fechar e abrir a OS.
- [ ] Confirmar persistência.

## 15. Financeiro

- [ ] Conferir lançamento criado pela OS de teste.
- [ ] Conferir valor.
- [ ] Conferir forma de pagamento.
- [ ] Confirmar que finalizar novamente uma OS finalizada não duplica lançamento.
- [ ] Conferir movimentos anteriores à atualização.

> A gestão avançada de pagamentos será ampliada em etapa própria. Este teste valida o comportamento atual.

## 16. Estoque

- [ ] Conferir saldo antes da OS.
- [ ] Conferir saldo depois da finalização.
- [ ] Conferir lote utilizado.
- [ ] Conferir movimentação de saída.
- [ ] Confirmar que nenhum saldo ficou negativo.
- [ ] Testar uma OS de teste com estoque insuficiente.
- [ ] Confirmar que a finalização é recusada.
- [ ] Confirmar que estoque não sofreu baixa parcial.
- [ ] Confirmar que financeiro não recebeu lançamento parcial.
- [ ] Confirmar que a OS continua em andamento.

## 17. Dashboard

- [ ] Abrir dashboard.
- [ ] Confirmar carregamento sem erro.
- [ ] Conferir indicadores.
- [ ] Conferir gráficos.
- [ ] Conferir rankings.
- [ ] Conferir alertas.
- [ ] Testar atualização da tela.
- [ ] Confirmar ausência de componentes duplicados ou telas vermelhas.

## 18. PDFs/documentos

- [ ] Gerar orçamento em PDF.
- [ ] Abrir PDF.
- [ ] Confirmar dados da empresa.
- [ ] Confirmar logo.
- [ ] Confirmar valores.
- [ ] Gerar documento da OS.
- [ ] Confirmar assinatura quando aplicável.
- [ ] Confirmar que documentos antigos continuam acessíveis quando armazenados.

## 19. Backup

- [ ] Abrir Configurações.
- [ ] Criar backup.
- [ ] Confirmar criação do arquivo ZIP.
- [ ] Compartilhar/salvar o arquivo fora do aplicativo.
- [ ] Confirmar atualização de data e tamanho do último backup.
- [ ] Confirmar que não apareceu erro.

## 20. Restauração — somente com dados de teste ou backup seguro

Antes deste passo, manter uma cópia externa do estado atual.

- [ ] Criar cliente identificável.
- [ ] Criar backup.
- [ ] Alterar esse cliente depois do backup.
- [ ] Restaurar o backup.
- [ ] Confirmar que o estado voltou ao momento do backup.
- [ ] Confirmar clientes.
- [ ] Confirmar veículos.
- [ ] Confirmar OS.
- [ ] Confirmar fotos.
- [ ] Confirmar fotos de avaria.
- [ ] Confirmar assinaturas.
- [ ] Confirmar logo.
- [ ] Confirmar assinatura da empresa.
- [ ] Fechar e abrir o aplicativo.
- [ ] Confirmar persistência depois da restauração.

## 21. Persistência final

- [ ] Fechar completamente o aplicativo.
- [ ] Abrir novamente.
- [ ] Reiniciar o celular.
- [ ] Abrir novamente.
- [ ] Confirmar clientes.
- [ ] Confirmar OS.
- [ ] Confirmar estoque.
- [ ] Confirmar financeiro.
- [ ] Confirmar fotos e assinaturas.

## 22. Encerramento

- [ ] Apagar somente os registros explicitamente criados para teste, quando seguro.
- [ ] Criar novo backup depois da validação.
- [ ] Guardar esse backup externamente.
- [ ] Registrar a versão do aplicativo testada.
- [ ] Registrar o commit correspondente.
- [ ] Marcar a versão como aprovada somente se não houver falhas críticas.
