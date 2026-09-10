import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
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

function somenteDigitos(valor: unknown): string {
  return String(valor ?? "").replace(/\D/g, "");
}

async function usuarioAutenticado(req: Request) {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return null;

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser();
  return error || !data.user ? null : data.user;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return json({ ok: false, code: "method_not_allowed", message: "Use POST." }, 405);
  }

  const user = await usuarioAutenticado(req);
  if (!user) {
    return json({ ok: false, code: "authentication_required", message: "Sessão inválida ou expirada." }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, code: "invalid_json", message: "JSON inválido." }, 400);
  }

  const provider = (Deno.env.get("FISCAL_DFE_PROVIDER") ?? "focusnfe").trim().toLowerCase();
  const token = Deno.env.get("FOCUS_NFE_TOKEN")?.trim() ?? "";
  const cnpj = somenteDigitos(Deno.env.get("FOCUS_NFE_CNPJ"));

  if (String(body.acao ?? "").trim().toLowerCase() === "status") {
    return json({
      ok: true,
      code: "status",
      provider,
      provider_configured: provider === "focusnfe" && token.length > 0,
      cnpj_configured: cnpj.length === 14,
      authenticated: true,
      auto_manifestacao: false,
      message: token.length > 0
        ? "Conector DF-e autenticado e configurado."
        : "Conector DF-e instalado, mas o token do provedor ainda não foi configurado.",
    });
  }

  const chave = somenteDigitos(body.chave);
  if (!/^\d{44}$/.test(chave)) {
    return json({ ok: false, code: "invalid_key", message: "Chave fiscal deve ter 44 dígitos." }, 400);
  }
  if (modeloDaChave(chave) !== 55) {
    return json({
      ok: false,
      code: "unsupported_model",
      message: "Este conector DF-e atende NF-e modelo 55. NFC-e modelo 65 usa QR/portal assistido.",
    }, 422);
  }
  if (provider !== "focusnfe") {
    return json({
      ok: false,
      code: "provider_not_supported",
      message: `Provedor fiscal não suportado nesta versão: ${provider}.`,
    }, 503);
  }
  if (!token) {
    return json({
      ok: false,
      code: "provider_not_configured",
      message: "NF-e 55 automática indisponível: configure FOCUS_NFE_TOKEN no Supabase. O XML manual continua disponível.",
    }, 503);
  }

  // O CNPJ, quando necessário, vem SOMENTE do segredo do servidor.
  // O aplicativo não pode sobrescrever esse valor no corpo da requisição.
  const url = new URL(`https://api.focusnfe.com.br/v2/nfes_recebidas/${chave}.xml`);
  if (cnpj.length === 14) url.searchParams.set("cnpj", cnpj);

  let resposta: Response;
  try {
    resposta = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Basic ${btoa(`${token}:`)}`,
        Accept: "application/xml,text/xml,application/json",
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
      message: "A NF-e ainda não está disponível para este CNPJ no provedor fiscal. Tente novamente depois ou importe o XML.",
    }, 404);
  }
  if (resposta.status === 401) {
    return json({
      ok: false,
      code: "provider_auth_error",
      message: "O provedor fiscal recusou o token configurado no servidor.",
    }, 502);
  }
  if (resposta.status === 403) {
    return json({
      ok: false,
      code: "provider_access_denied",
      message: "O provedor localizou a operação, mas não liberou o XML completo para esta empresa.",
    }, 409);
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

  // Não realizamos manifestação automaticamente. A distribuição pode entregar
  // apenas resNFe até que a empresa execute conscientemente o evento fiscal.
  if (!/<(?:\w+:)?infNFe\b/i.test(texto)) {
    return json({
      ok: false,
      code: "document_not_complete",
      manifestation_required: true,
      auto_manifestacao: false,
      message: "A NF-e foi localizada, mas o XML completo ainda não está disponível. Se o provedor exigir manifestação do destinatário, ela deve ser feita explicitamente pela empresa.",
    }, 409);
  }

  return json({
    ok: true,
    code: "document_complete",
    provider: "focusnfe",
    chave,
    xml: texto,
    auto_manifestacao: false,
  });
});
