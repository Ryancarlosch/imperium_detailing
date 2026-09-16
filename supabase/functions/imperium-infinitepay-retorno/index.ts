import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const INFINITEPAY_HANDLE = "imperium_detailing";
const DEFAULT_WEB_URL =
  "https://imperium-manager-web-vercel-git-vercel-web-ryancarlos148-2812.vercel.app/";
const MOBILE_RETURN_URL = "imperiumdetailing://payment-return/";

function normalizarReturnUrl(raw: unknown): string {
  const valor = String(raw ?? "").trim();
  const candidatos = valor ? [valor, DEFAULT_WEB_URL] : [DEFAULT_WEB_URL];

  for (const candidato of candidatos) {
    try {
      const url = new URL(candidato);
      const host = url.hostname.toLowerCase();

      if (
        url.protocol === "imperiumdetailing:" &&
        host === "payment-return"
      ) {
        return MOBILE_RETURN_URL;
      }

      const local = host === "localhost" || host === "127.0.0.1";
      const vercelImperium =
        host === "imperium-manager-web-vercel.vercel.app" ||
        (host.startsWith("imperium-manager-web-vercel") &&
          host.endsWith(".vercel.app"));

      if (!vercelImperium && !local) continue;
      if (local && url.protocol !== "http:" && url.protocol !== "https:") continue;
      if (!local && url.protocol !== "https:") continue;

      return `${url.protocol}//${url.host}/`;
    } catch (_) {
      // tenta próximo candidato
    }
  }

  return DEFAULT_WEB_URL;
}

function redirectToApp(
  returnUrl: unknown,
  status: "confirmado" | "processando" | "erro",
  orderNsu = "",
) {
  const target = new URL(normalizarReturnUrl(returnUrl));
  target.searchParams.set("imperium_pagamento", status);
  if (orderNsu.trim()) {
    target.searchParams.set("order_nsu", orderNsu.trim());
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: target.toString(),
      "Cache-Control": "no-store, no-cache, must-revalidate",
      Pragma: "no-cache",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Método não permitido.", { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const url = new URL(req.url);
  const orderNsu = (url.searchParams.get("order_nsu") ?? "").trim();
  const transactionNsu = (url.searchParams.get("transaction_nsu") ?? "").trim();
  const slug = (url.searchParams.get("slug") ?? "").trim();
  const receiptUrl = (url.searchParams.get("receipt_url") ?? "").trim();
  const captureMethod = (url.searchParams.get("capture_method") ?? "").trim();

  if (!supabaseUrl || !serviceRoleKey) {
    return redirectToApp(null, "processando", orderNsu);
  }

  if (!orderNsu) {
    return redirectToApp(null, "processando");
  }

  const service = createClient(supabaseUrl, serviceRoleKey);
  const { data: cobranca } = await service
    .from("imperium_assinatura_cobrancas")
    .select(
      "order_nsu,status,valor_centavos,plano_nome,transaction_nsu,return_url",
    )
    .eq("order_nsu", orderNsu)
    .maybeSingle();

  if (!cobranca) {
    return redirectToApp(null, "erro", orderNsu);
  }

  if (cobranca.status === "pago") {
    return redirectToApp(cobranca.return_url, "confirmado", orderNsu);
  }

  if (!transactionNsu || !slug) {
    return redirectToApp(cobranca.return_url, "processando", orderNsu);
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
        return redirectToApp(cobranca.return_url, "confirmado", orderNsu);
      }

      console.error("infinitepay_return_confirm_error", error);
    }
  } catch (error) {
    console.error("infinitepay_return_payment_check_error", error);
  }

  return redirectToApp(cobranca.return_url, "processando", orderNsu);
});
