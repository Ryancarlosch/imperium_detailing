import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const INFINITEPAY_HANDLE = "imperium_detailing";

function htmlPage(title: string, message: string, ok: boolean) {
  const accent = ok ? "#22c55e" : "#f59e0b";
  return new Response(
    `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{margin:0;background:#070b14;color:#f8fafc;font-family:Arial,sans-serif;display:grid;place-items:center;min-height:100vh;padding:24px;box-sizing:border-box}.card{max-width:520px;background:#111827;border:1px solid #263244;border-radius:18px;padding:28px;text-align:center;box-shadow:0 18px 50px rgba(0,0,0,.35)}.icon{width:58px;height:58px;border-radius:50%;display:grid;place-items:center;margin:0 auto 18px;background:${accent}22;color:${accent};font-size:30px;font-weight:bold}h1{font-size:24px;margin:0 0 12px}p{color:#cbd5e1;line-height:1.55;margin:0}.brand{margin-top:22px;color:#64748b;font-size:13px}</style></head><body><div class="card"><div class="icon">${ok ? "✓" : "…"}</div><h1>${title}</h1><p>${message}</p><div class="brand">Imperium Manager</div></div></body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Método não permitido.", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return htmlPage(
      "Pagamento recebido",
      "Volte ao Imperium em alguns instantes e atualize a tela do plano.",
      false,
    );
  }

  const url = new URL(req.url);
  const orderNsu = (url.searchParams.get("order_nsu") ?? "").trim();
  const transactionNsu = (url.searchParams.get("transaction_nsu") ?? "").trim();
  const slug = (url.searchParams.get("slug") ?? "").trim();
  const receiptUrl = (url.searchParams.get("receipt_url") ?? "").trim();
  const captureMethod = (url.searchParams.get("capture_method") ?? "").trim();

  if (!orderNsu) {
    return htmlPage(
      "Pagamento em processamento",
      "A confirmação está sendo processada. Volte ao Imperium e atualize a tela do plano.",
      false,
    );
  }

  const service = createClient(supabaseUrl, serviceRoleKey);
  const { data: cobranca } = await service
    .from("imperium_assinatura_cobrancas")
    .select("order_nsu,status,valor_centavos,plano_nome,transaction_nsu")
    .eq("order_nsu", orderNsu)
    .maybeSingle();

  if (!cobranca) {
    return htmlPage(
      "Pedido não localizado",
      "Volte ao Imperium e tente abrir o checkout novamente.",
      false,
    );
  }

  if (cobranca.status === "pago") {
    return htmlPage(
      "Pagamento confirmado",
      "Seu plano já foi liberado. Você pode fechar esta aba, voltar ao Imperium e atualizar a tela do plano.",
      true,
    );
  }

  if (!transactionNsu || !slug) {
    return htmlPage(
      "Pagamento em processamento",
      "Recebemos o retorno da InfinitePay. A confirmação automática continuará pelo webhook. Volte ao Imperium em alguns instantes.",
      false,
    );
  }

  try {
    const response = await fetch("https://api.checkout.infinitepay.io/payment_check", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        handle: INFINITEPAY_HANDLE,
        order_nsu: orderNsu,
        transaction_nsu: transactionNsu,
        slug,
      }),
    });

    const provider = (await response.json()) as Record<string, unknown>;
    const paid = response.ok && provider.paid === true;
    const amount = Number(provider.amount ?? 0);

    if (paid && Number.isInteger(amount) && amount === cobranca.valor_centavos) {
      const paidAmount = Number(provider.paid_amount ?? amount);
      const installments = Number(provider.installments ?? 1);
      const method = String(provider.capture_method ?? captureMethod).trim();

      const { error } = await service.rpc(
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
          p_capture_method: method,
          p_receipt_url: receiptUrl,
          p_payload: {
            redirect: Object.fromEntries(url.searchParams.entries()),
            payment_check: provider,
          },
        },
      );

      if (!error) {
        return htmlPage(
          "Pagamento confirmado",
          "Seu plano foi liberado. Feche esta aba, volte ao Imperium e atualize a tela do plano.",
          true,
        );
      }

      console.error("infinitepay_return_confirm_error", error);
    }
  } catch (error) {
    console.error("infinitepay_return_payment_check_error", error);
  }

  return htmlPage(
    "Pagamento em processamento",
    "Ainda estamos aguardando a confirmação final da InfinitePay. Volte ao Imperium em alguns instantes e atualize a tela do plano.",
    false,
  );
});
