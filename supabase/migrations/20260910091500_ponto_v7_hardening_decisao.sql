-- Imperium Manager - Ponto V7 hardening
-- Torna explícito que a decisão administrativa precisa ser booleana.

create or replace function public.ponto_decidir_solicitacao_ajuste(
  p_solicitacao_id uuid,
  p_aprovar boolean,
  p_motivo text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_solicitacao public.ponto_solicitacoes_ajuste%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_ajuste jsonb;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if p_aprovar is null then
    raise exception 'Informe se a solicitação deve ser aprovada ou rejeitada.';
  end if;

  select *
    into v_solicitacao
  from public.ponto_solicitacoes_ajuste s
  where s.id = p_solicitacao_id
  for update;

  if not found then
    raise exception 'Solicitação não encontrada.';
  end if;

  if not private.usuario_admin_empresa(v_solicitacao.empresa_id) then
    raise exception 'Somente administradores da empresa podem decidir solicitações.';
  end if;

  if v_solicitacao.status <> 'Pendente' then
    raise exception 'Esta solicitação já foi decidida.';
  end if;

  if not p_aprovar and char_length(v_motivo) < 5 then
    raise exception 'Informe o motivo da rejeição com pelo menos 5 caracteres.';
  end if;

  if p_aprovar then
    v_ajuste := public.ponto_salvar_registro_admin(
      v_solicitacao.empresa_id,
      v_solicitacao.colaborador_id,
      v_solicitacao.data,
      v_solicitacao.situacao_solicitada,
      v_solicitacao.entrada_solicitada,
      v_solicitacao.intervalo_inicio_solicitado,
      v_solicitacao.intervalo_fim_solicitado,
      v_solicitacao.saida_solicitada,
      v_solicitacao.observacoes_solicitadas,
      concat(
        'Solicitação do funcionário: ',
        v_solicitacao.motivo,
        case when v_motivo = '' then '' else concat(' | Aprovação: ', v_motivo) end
      )
    );
  end if;

  update public.ponto_solicitacoes_ajuste
  set
    status = case when p_aprovar then 'Aprovada' else 'Rejeitada' end,
    atualizado_em = now(),
    decidido_em = now(),
    decidido_por = auth.uid(),
    decisao_motivo = case
      when p_aprovar and v_motivo = '' then 'Aprovada pelo administrador'
      else v_motivo
    end
  where id = p_solicitacao_id
  returning * into v_solicitacao;

  return jsonb_build_object(
    'solicitacao', to_jsonb(v_solicitacao),
    'registro', v_ajuste
  );
end;
$$;
