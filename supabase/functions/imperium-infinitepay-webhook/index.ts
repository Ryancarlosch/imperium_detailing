import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const INFINITEPAY_HANDLE = "imperium_detailing";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

async function confirmarNaInfinitePay(params: {
  orderNsu: string;
  transactionNsu: string;
  slug: string;
}) {
  const response = await fetch("https://api.checkout.infinitepay.io/payment_check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      handle: INFINITEPAY_HANDLE,
      order_nsu: params.orderNsu,
      transaction_nsu: params.transactionNsu,
      slug: params.slug,
    }),
  });

  const text = await response.text();
  let body: Record<string, unknown> = {};
  if (text.trim()) {
    try {
      body = JSON.parse(text) as Record<string, unknown>;
    } catch (_) {
      body = { raw: text.slice(0, 1000) };
    }
  }

  return { response, body };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ success: false, message: "Método não permitido." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ success: false, message: "Servidor indisponível." }, 500);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch (_) {
    return json({ success: false, message: "Payload inválido." }, 400);
  }

  const orderNsu = String(payload.order_nsu ?? "").trim();
  const transactionNsu = String(payload.transaction_nsu ?? "").trim();
  const slug = String(payload.invoice_slug ?? payload.slug ?? "").trim();

  if (!orderNsu || !transactionNsu || !slug) {
    return json(
      { success: false, message: "Identificadores do pagamento ausentes." },
      400,
    );
  }

  const service = createClient(supabaseUrl, serviceRoleKey);
  const { data: cobranca, error: cobrancaError } = await service
    .from("imperium_assinatura_cobrancas")
    .select("order_nsu,status,valor_centavos,transaction_nsu")
    .eq("order_nsu", orderNsu)
    .maybeSingle();

  if (cobrancaError) {
    console.error("infinitepay_webhook_cobranca_error", cobrancaError);
    return json({ success: false, message: "Erro ao localizar cobrança." }, 400);
  }

  if (!cobranca) {
    return json({ success: false, message: "Pedido não encontrado." }, 400);
  }

  if (cobranca.status === "pago") {
    if (cobranca.transaction_nsu && cobranca.transaction_nsu !== transactionNsu) {
      return json(
        { success: false, message: "Pedido já confirmado por outra transação." },
        400,
      );
    }
    return json({ success: true, message: null }, 200);
  }

  let provider;
  try {
    provider = await confirmarNaInfinitePay({ orderNsu, transactionNsu, slug });
  } catch (error) {
    console.error("infinitepay_payment_check_network_error", error);
    return json(
      { success: false, message: "Não foi possível validar o pagamento." },
      400,
    );
  }

  if (!provider.response.ok) {
    console.error("infinitepay_payment_check_http_error", {
      status: provider.response.status,
      body: provider.body,
    });
    return json(
      { success: false, message: "InfinitePay não confirmou o pagamento." },
      400,
    );
  }

  const paid = provider.body.paid === true;
  const amount = Number(provider.body.amount ?? 0);
  const paidAmount = Number(provider.body.paid_amount ?? amount);
  const installments = Number(provider.body.installments ?? payload.installments ?? 1);
  const captureMethod = String(
    provider.body.capture_method ?? payload.capture_method ?? "",
  ).trim();

  if (!paid) {
    return json({ success: false, message: "Pagamento ainda não aprovado." }, 400);
  }

  if (!Number.isInteger(amount) || amount !== cobranca.valor_centavos) {
    console.error("infinitepay_amount_mismatch", {
      expected: cobranca.valor_centavos,
      received: amount,
      orderNsu,
    });
    return json({ success: false, message: "Valor do pagamento inválido." }, 400);
  }

  const { error: confirmarError } = await service.rpc(
    "imperium_confirmar_pagamento_infinitepay",
    {
      p_order_nsu: orderNsu,
      p_transaction_nsu: transactionNsu,
      p_invoice_slug: slug,
      p_amount_centavos: amount,
      p_paid_amount_centavos: Number.isFinite(paidAmount)
        ? Math.round(paidAmount)
        : amount,
      p_installments: Number.isFinite(installments)
        ? Math.max(1, Math.round(installments))
        : 1,
      p_capture_method: captureMethod,
      p_receipt_url: String(payload.receipt_url ?? "").trim(),
      p_payload: { webhook: payload, payment_check: provider.body },
    },
  );

  if (confirmarError) {
    console.error("infinitepay_confirmar_pagamento_error", confirmarError);
    return json(
      { success: false, message: "Pagamento validado, mas a licença não foi atualizada." },
      400,
    );
  }

  return json({ success: true, message: null }, 200);
});
