import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function normalizarPlaca(valor: unknown): string {
  return String(valor ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Método não permitido." }, 405);
  }

  // consulta-placa-edge-auth-v1
  const authorization = req.headers.get("Authorization") ?? "";

  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "Usuário não autenticado." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    return json({ error: "Configuração do Supabase indisponível." }, 503);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return json({ error: "Sessão inválida ou expirada." }, 401);
  }

  let body: Record<string, unknown>;

  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Corpo da requisição inválido." }, 400);
  }

  const placa = normalizarPlaca(body.placa);

  if (!/^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/.test(placa)) {
    return json(
      { error: "Informe uma placa válida no padrão antigo ou Mercosul." },
      400,
    );
  }

  // A chave do provedor fica somente como secret no Supabase.
  // Nunca colocar esse token no Flutter/APK.
  const token = Deno.env.get("FALCON_DATAHUB_TOKEN");

  if (!token) {
    return json(
      { error: "Consulta por placa ainda não foi configurada no servidor." },
      503,
    );
  }

  const endpoint =
    `https://datahub.falcon-server.com.br/private/v1/placas/${placa}/search`;

  let providerResponse: Response;

  try {
    providerResponse = await fetch(endpoint, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
  } catch (_) {
    return json(
      { error: "Serviço de consulta de placa temporariamente indisponível." },
      502,
    );
  }

  if (providerResponse.status === 404) {
    return json({ error: "Placa não encontrada." }, 404);
  }

  if (!providerResponse.ok) {
    return json(
      { error: "O provedor de consulta de placa recusou a consulta." },
      502,
    );
  }

  let providerBody: Record<string, unknown>;

  try {
    providerBody = await providerResponse.json();
  } catch (_) {
    return json({ error: "Resposta inválida do provedor de placa." }, 502);
  }

  const raw =
    providerBody.data && typeof providerBody.data === "object"
      ? (providerBody.data as Record<string, unknown>)
      : providerBody;

  // Retorna ao aplicativo somente os campos necessários ao cadastro.
  return json({
    data: {
      placa,
      marca: String(raw.marca ?? "").trim(),
      modelo: String(raw.modelo ?? "").trim(),
      ano_fabricacao: Number(raw.ano ?? raw.ano_fabricacao ?? 0),
      ano_modelo: Number(raw.ano_modelo ?? raw.ano ?? 0),
      cor: String(raw.cor ?? "").trim(),
    },
  });
});