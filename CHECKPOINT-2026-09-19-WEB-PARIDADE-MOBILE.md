# CHECKPOINT — Paridade funcional Mobile → Web

Data: 2026-09-19
Branch oficial: `desenvolvimento`

## Resultado da revisão

O workspace Web cobre os fluxos de negócio compartilháveis com o Mobile sem criar banco, autenticação ou regras paralelas. Ambos usam o mesmo tenant, as mesmas tabelas Cloud, RLS e buckets privados.

Módulos presentes no Web:

- dashboard gerencial e busca global;
- clientes, veículos, agenda e histórico;
- ordens de serviço, criação, edição com CAS, cancelamento e finalização transacional;
- produtos da OS, PDF, fotos, checklist, avarias e assinatura;
- estoque, produtos, lotes, movimentações, reservas e alertas;
- fluxo de caixa, lançamentos, contas, DRE, relatórios e estornos;
- gestão financeira administrativa, fornecedores, taxas, custos fixos, metas, plano de contas, mão de obra, previsto x realizado e transferências;
- CRM, orçamentos, precificação, serviços, pós-venda e marketing;
- ponto, funcionários, solicitações e pagamentos;
- usuários, acessos, configurações da empresa, Central Cloud e pendências;
- fotos/galeria;
- notas fiscais e XML Cloud.

## Lacuna encerrada neste lote

A página Web de arquivos da OS deixou de ser somente leitura. Em OS `Aberta` ou `Em andamento`, agora permite:

- enviar foto nas etapas Antes, Durante e Depois;
- criar e editar itens do checklist;
- registrar avaria, localização e foto;
- capturar e substituir a assinatura do cliente;
- visualizar os mesmos arquivos sincronizados;
- gerar o PDF da OS.

As gravações usam:

- bucket privado `imperium-os-arquivos`;
- caminho segregado por `empresa_id` e OS;
- SHA-256 e nomes determinísticos;
- origem Web persistente/idempotente;
- soft delete de metadados já existente;
- CAS por `atualizado_em` na edição concorrente de checklist e assinatura;
- bloqueio de escrita para OS fora dos estados editáveis.

## Gate automatizado

O lote amplia `test/web_os_arquivos_source_test.dart` para proteger upload privado, origem idempotente, CAS, seleção de imagem, assinatura por bytes e ausência de `dart:io`/URL pública no Web.

Também foi corrigido um teste antigo de navegação administrativa para aceitar novos módulos no grupo sem exigir um conjunto fechado de índices.

## Limite correto da paridade

Recursos dependentes do aparelho continuam nativos por definição:

- câmera e scanner;
- notificações locais;
- backup/restauração do SQLite local;
- instalação e atualização do aplicativo;
- integrações do sistema operacional.

O Web expõe e administra os dados sincronizados resultantes quando isso faz sentido. Esses recursos não devem ser duplicados artificialmente no navegador.

## Pendências externas ao código

- homologar Android ↔ Web simultaneamente em dois dispositivos;
- percorrer os perfis de acesso em um tenant de homologação;
- validar o lote no CI com análise, testes, build Web e build APK.
