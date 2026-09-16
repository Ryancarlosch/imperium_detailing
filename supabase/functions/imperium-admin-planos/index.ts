import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const IMPERIUM_EMPRESA_ID = "dbbf4114-06fa-46b8-a2f6-50b3f3ead436";
const ADMIN_ROLES = new Set([
  "admin",
  "administrador",
  "proprietario",
  "proprietário",
  "dono",
  "owner",
]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function slugPlano(nome: string) {
  return nome
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 50);
}

function inteiro(valor: unknown): number | null {
  const numero = typeof valor === "number" ? valor : Number(valor);
  if (!Number.isFinite(numero) || !Number.isInteger(numero)) return null;
  return numero;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Método não permitido." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = req.headers.get("Authorization") ?? "";

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Configuração do servidor indisponível." }, 503);
  }

  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "Usuário não autenticado." }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const service = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return json({ error: "Sessão inválida ou expirada." }, 401);
  }

  const { data: vinculo, error: vinculoError } = await service
    .from("empresa_usuarios")
    .select("papel,ativo")
    .eq("empresa_id", IMPERIUM_EMPRESA_ID)
    .eq("user_id", user.id)
    .eq("ativo", true)
    .maybeSingle();

  const papel = String(vinculo?.papel ?? "").trim().toLowerCase();
  if (vinculoError || !vinculo || !ADMIN_ROLES.has(papel)) {
    return json(
      { error: "Acesso restrito ao administrador comercial do Imperium." },
      403,
    );
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Corpo da requisição inválido." }, 400);
  }

  const action = String(body.action ?? "list").trim().toLowerCase();

  if (action === "list") {
    const { data, error } = await service
      .from("imperium_planos_assinatura")
      .select(
        "codigo,nome,meses,valor_centavos,moeda,ativo,ordem,criado_em,atualizado_em",
      )
      .order("ordem", { ascending: true })
      .order("meses", { ascending: true })
      .order("codigo", { ascending: true });

    if (error) {
      console.error("imperium_admin_planos_list_error", error);
      return json({ error: "Não foi possível carregar os planos." }, 500);
    }

    return json({ planos: data ?? [] });
  }

  if (action !== "save") {
    return json({ error: "Ação inválida." }, 400);
  }

  const codigoInformado = String(body.codigo ?? "").trim().toLowerCase();
  const nome = String(body.nome ?? "").trim();
  const meses = inteiro(body.meses);
  const valorCentavos = inteiro(body.valor_centavos);
  const ordem = inteiro(body.ordem ?? 0);
  const ativo = body.ativo !== false;

  if (nome.length < 2 || nome.length > 80) {
    return json({ error: "O nome do plano deve ter entre 2 e 80 caracteres." }, 400);
  }
  if (meses == null || meses < 1 || meses > 120) {
    return json({ error: "A duração deve ficar entre 1 e 120 meses." }, 400);
  }
  if (valorCentavos == null || valorCentavos < 1 || valorCentavos > 100000000) {
    return json({ error: "Informe um valor válido para o plano." }, 400);
  }
  if (ordem == null || ordem < 0 || ordem > 10000) {
    return json({ error: "A ordem de exibição deve ficar entre 0 e 10000." }, 400);
  }

  if (codigoInformado) {
    if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(codigoInformado)) {
      return json({ error: "Código do plano inválido." }, 400);
    }

    const { data, error } = await service
      .from("imperium_planos_assinatura")
      .update({
        nome,
        meses,
        valor_centavos: valorCentavos,
        moeda: "BRL",
        ativo,
        ordem,
        atualizado_em: new Date().toISOString(),
      })
      .eq("codigo", codigoInformado)
      .select(
        "codigo,nome,meses,valor_centavos,moeda,ativo,ordem,criado_em,atualizado_em",
      )
      .maybeSingle();

    if (error) {
      console.error("imperium_admin_planos_update_error", error);
      return json({ error: "Não foi possível atualizar o plano." }, 500);
    }
    if (!data) {
      return json({ error: "Plano não encontrado." }, 404);
    }

    return json({ plano: data });
  }

  let codigo = slugPlano(nome);
  if (!codigo) codigo = "plano";

  const { data: conflito, error: conflitoError } = await service
    .from("imperium_planos_assinatura")
    .select("codigo")
    .eq("codigo", codigo)
    .maybeSingle();

  if (conflitoError) {
    console.error("imperium_admin_planos_conflict_error", conflitoError);
    return json({ error: "Não foi possível validar o novo plano." }, 500);
  }

  if (conflito) {
    codigo = `${codigo.slice(0, 42)}-${crypto.randomUUID().replaceAll("-", "").slice(0, 7)}`;
  }

  const { data, error } = await service
    .from("imperium_planos_assinatura")
    .insert({
      codigo,
      nome,
      meses,
      valor_centavos: valorCentavos,
      moeda: "BRL",
      ativo,
      ordem,
    })
    .select(
      "codigo,nome,meses,valor_centavos,moeda,ativo,ordem,criado_em,atualizado_em",
    )
    .single();

  if (error) {
    console.error("imperium_admin_planos_insert_error", error);
    return json({ error: "Não foi possível criar o plano." }, 500);
  }

  return json({ plano: data }, 201);
});
