import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function modeloDaChave(chave: string): number {
  return Number.parseInt(chave.slice(20, 22), 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return json({ ok: false, code: "method_not_allowed", message: "Use POST." }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, code: "invalid_json", message: "JSON inválido." }, 400);
  }

  const chave = String(body.chave ?? "").replace(/\D/g, "");
  if (!/^\d{44}$/.test(chave)) {
    return json({ ok: false, code: "invalid_key", message: "Chave fiscal deve ter 44 dígitos." }, 400);
  }
  if (modeloDaChave(chave) !== 55) {
    return json({
      ok: false,
      code: "unsupported_model",
      message: "Este conector DF-e atende NF-e modelo 55. NFC-e modelo 65 usa o fluxo QR/portal assistido.",
    }, 422);
  }

  const provider = (Deno.env.get("FISCAL_DFE_PROVIDER") ?? "focusnfe").toLowerCase();
  if (provider !== "focusnfe") {
    return json({
      ok: false,
      code: "provider_not_supported",
      message: `Provedor fiscal não suportado nesta versão: ${provider}.`,
    }, 503);
  }

  const token = Deno.env.get("FOCUS_NFE_TOKEN")?.trim();
  if (!token) {
    return json({
      ok: false,
      code: "provider_not_configured",
      message: "Conector DF-e instalado, mas FOCUS_NFE_TOKEN ainda não foi configurado no Supabase.",
    }, 503);
  }

  const cnpj = String(body.cnpj ?? Deno.env.get("FOCUS_NFE_CNPJ") ?? "").replace(/\D/g, "");
  const url = new URL(`https://api.focusnfe.com.br/v2/nfes_recebidas/${chave}.xml`);
  if (cnpj.length === 14) url.searchParams.set("cnpj", cnpj);

  let resposta: Response;
  try {
    resposta = await fetch(url, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${btoa(`${token}:`)}`,
        "Accept": "application/xml,text/xml,application/json",
      },
      redirect: "follow",
    });
  } catch (error) {
    return json({
      ok: false,
      code: "provider_unavailable",
      message: `Falha de rede ao consultar o provedor fiscal: ${String(error)}`,
    }, 502);
  }

  const texto = await resposta.text();
  if (resposta.status === 404) {
    return json({
      ok: false,
      code: "document_not_found",
      message: "A NF-e não está disponível para esta empresa no provedor fiscal.",
    }, 404);
  }
  if (resposta.status === 401 || resposta.status === 403) {
    return json({
      ok: false,
      code: "provider_auth_error",
      message: "O provedor fiscal recusou as credenciais ou o acesso à NF-e.",
    }, 502);
  }
  if (!resposta.ok) {
    return json({
      ok: false,
      code: "provider_error",
      message: `O provedor fiscal respondeu HTTP ${resposta.status}.`,
    }, 502);
  }

  const normalizado = texto.replace(/\s+/g, " ");
  if (!texto.trim().startsWith("<") || !normalizado.includes(chave)) {
    return json({
      ok: false,
      code: "invalid_provider_payload",
      message: "O provedor respondeu, mas não entregou XML correspondente à chave solicitada.",
    }, 502);
  }

  // A distribuição pode entregar primeiro apenas resNFe (resumo). Não fazemos
  // manifestação automática: esse evento fiscal deve ser decisão explícita.
  if (!/<(?:\w+:)?infNFe\b/i.test(texto)) {
    return json({
      ok: false,
      code: "document_not_complete",
      message: "A NF-e foi localizada, mas o XML completo ainda não está disponível. A manifestação do destinatário, quando necessária, deve ser feita de forma explícita no provedor fiscal.",
    }, 409);
  }

  return json({ ok: true, provider: "focusnfe", chave, xml: texto });
});
