import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const INFINITEPAY_HANDLE = "imperium_detailing";
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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Corpo da requisição inválido." }, 400);
  }

  const empresaId = String(body.empresa_id ?? "").trim();
  const planoCodigo = String(body.plano_codigo ?? "")
    .trim()
    .toLowerCase();

  if (!empresaId || !planoCodigo) {
    return json({ error: "Empresa e plano são obrigatórios." }, 400);
  }

  const { data: vinculo, error: vinculoError } = await service
    .from("empresa_usuarios")
    .select("empresa_id,papel,ativo")
    .eq("empresa_id", empresaId)
    .eq("user_id", user.id)
    .eq("ativo", true)
    .in("papel", ["admin", "proprietario"])
    .maybeSingle();

  if (vinculoError) {
    console.error("infinitepay_vinculo_error", vinculoError);
    return json({ error: "Não foi possível validar a empresa." }, 500);
  }

  if (!vinculo) {
    return json(
      { error: "Somente o administrador ou proprietário pode contratar o plano." },
      403,
    );
  }

  const { data: empresa, error: empresaError } = await service
    .from("empresas")
    .select("id,nome,ativo")
    .eq("id", empresaId)
    .eq("ativo", true)
    .maybeSingle();

  if (empresaError || !empresa) {
    return json({ error: "Empresa não encontrada ou desativada." }, 404);
  }

  const { data: plano, error: planoError } = await service
    .from("imperium_planos_assinatura")
    .select("codigo,nome,meses,valor_centavos,moeda,ativo")
    .eq("codigo", planoCodigo)
    .eq("ativo", true)
    .maybeSingle();

  if (planoError) {
    console.error("infinitepay_plano_error", planoError);
    return json({ error: "Não foi possível consultar os planos." }, 500);
  }

  if (!plano) {
    return json({ error: "Plano inválido ou indisponível." }, 400);
  }

  const orderNsu = `imp-${crypto.randomUUID()}`;

  const { error: insertError } = await service
    .from("imperium_assinatura_cobrancas")
    .insert({
      empresa_id: empresaId,
      user_id: user.id,
      plano_codigo: plano.codigo,
      plano_nome: plano.nome,
      plano_meses: plano.meses,
      valor_centavos: plano.valor_centavos,
      moeda: plano.moeda,
      order_nsu: orderNsu,
      status: "pendente",
    });

  if (insertError) {
    console.error("infinitepay_cobranca_insert_error", insertError);
    return json({ error: "Não foi possível iniciar a cobrança." }, 500);
  }

  const functionBase = `${supabaseUrl}/functions/v1`;
  const customerName = String(
    user.user_metadata?.full_name ??
      user.user_metadata?.name ??
      empresa.nome ??
      "",
  ).trim();

  const payload: Record<string, unknown> = {
    handle: INFINITEPAY_HANDLE,
    redirect_url: `${functionBase}/imperium-infinitepay-retorno`,
    webhook_url: `${functionBase}/imperium-infinitepay-webhook`,
    order_nsu: orderNsu,
    items: [
      {
        quantity: 1,
        price: plano.valor_centavos,
        description: `Imperium Manager - Plano ${plano.nome}`,
      },
    ],
  };

  if (user.email) {
    payload.customer = {
      email: user.email,
      ...(customerName ? { name: customerName } : {}),
    };
  }

  let providerResponse: Response;
  let providerBody: Record<string, unknown> = {};

  try {
    providerResponse = await fetch("https://api.checkout.infinitepay.io/links", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const text = await providerResponse.text();
    if (text.trim()) {
      try {
        providerBody = JSON.parse(text) as Record<string, unknown>;
      } catch (_) {
        providerBody = { raw: text.slice(0, 1000) };
      }
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await service
      .from("imperium_assinatura_cobrancas")
      .update({
        status: "falhou",
        erro: `Falha de conexão com a InfinitePay: ${message}`.slice(0, 500),
        atualizado_em: new Date().toISOString(),
      })
      .eq("order_nsu", orderNsu);

    return json(
      { error: "Não foi possível conectar à InfinitePay. Tente novamente." },
      502,
    );
  }

  const checkoutUrl = String(providerBody.url ?? "").trim();

  if (!providerResponse.ok || !checkoutUrl) {
    const providerMessage = String(
      providerBody.message ?? providerBody.error ?? "Checkout não criado.",
    ).trim();

    console.error("infinitepay_checkout_error", {
      status: providerResponse.status,
      body: providerBody,
    });

    await service
      .from("imperium_assinatura_cobrancas")
      .update({
        status: "falhou",
        provider_payload: providerBody,
        erro: providerMessage.slice(0, 500),
        atualizado_em: new Date().toISOString(),
      })
      .eq("order_nsu", orderNsu);

    return json(
      {
        error:
          providerMessage ||
          "A InfinitePay não conseguiu criar o checkout. Verifique se o Checkout Integrado está habilitado.",
      },
      providerResponse.status >= 400 && providerResponse.status < 500 ? 400 : 502,
    );
  }

  const { error: updateError } = await service
    .from("imperium_assinatura_cobrancas")
    .update({
      checkout_url: checkoutUrl,
      provider_payload: providerBody,
      atualizado_em: new Date().toISOString(),
    })
    .eq("order_nsu", orderNsu);

  if (updateError) {
    console.error("infinitepay_cobranca_update_error", updateError);
  }

  return json({
    url: checkoutUrl,
    order_nsu: orderNsu,
    plano: plano.nome,
    valor_centavos: plano.valor_centavos,
  });
});
