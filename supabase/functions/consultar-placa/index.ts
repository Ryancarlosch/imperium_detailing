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
    global: { headers: { Authorization: authorization } },
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

  const token = (Deno.env.get("FALCON_DATAHUB_TOKEN") ?? "").trim();
  if (!token) {
    return json(
      { error: "Consulta por placa ainda não foi configurada no servidor." },
      503,
    );
  }

  const endpoint =
    `https://datahub.falcon-server.com.br/private/v1/placas/${placa}/search`;

  let response: Response;
  let providerBody: Record<string, unknown> | null = null;

  try {
    response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
  } catch (_) {
    return json(
      { error: "Não foi possível conectar ao provedor de placas." },
      502,
    );
  }

  try {
    const parsed = await response.json();
    if (parsed && typeof parsed === "object") {
      providerBody = parsed as Record<string, unknown>;
    }
  } catch (_) {
    providerBody = null;
  }

  console.log(
    JSON.stringify({
      evento: "falcon_placa_status",
      status: response.status,
      placa,
      body_keys: providerBody ? Object.keys(providerBody) : [],
    }),
  );

  if (!response.ok) {
    let mensagem = "Falha ao consultar placa no Falcon.";
    if (providerBody) {
      const candidato =
        providerBody.error ?? providerBody.message ?? providerBody.mensagem;
      if (typeof candidato === "string" && candidato.trim()) {
        mensagem = candidato.trim();
      }
    }

    if (response.status === 401) {
      mensagem = "API Key do Falcon inválida ou expirada.";
    } else if (response.status === 403) {
      mensagem = "API Key do Falcon sem permissão para consulta de placas.";
    } else if (response.status === 404) {
      mensagem = "Placa não encontrada na base do Falcon.";
    } else if (response.status === 429) {
      mensagem = "Limite de consultas do plano Falcon atingido.";
    }

    return json(
      { error: mensagem, provider_status: response.status },
      response.status,
    );
  }

  if (!providerBody) {
    return json({ error: "O Falcon respondeu sem JSON válido." }, 502);
  }

  const raw =
    providerBody.data && typeof providerBody.data === "object"
      ? (providerBody.data as Record<string, unknown>)
      : providerBody;

  const marca = String(raw.marca ?? raw.brand ?? "").trim();
  const modelo = String(raw.modelo ?? raw.model ?? "").trim();
  const cor = String(raw.cor ?? raw.color ?? "").trim();
  const anoFabricacao = Number(
    raw.ano ?? raw.ano_fabricacao ?? raw.year ?? raw.year_manufacture ?? 0,
  );
  const anoModelo = Number(
    raw.ano_modelo ?? raw.model_year ?? raw.ano ?? raw.year ?? 0,
  );

  if (!marca && !modelo) {
    return json(
      { error: "O Falcon respondeu, mas não retornou marca/modelo do veículo." },
      502,
    );
  }

  return json({
    data: {
      placa,
      marca,
      modelo,
      ano_fabricacao: anoFabricacao,
      ano_modelo: anoModelo,
      cor,
    },
  });
});