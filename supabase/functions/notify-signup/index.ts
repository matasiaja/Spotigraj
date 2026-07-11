import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const NOTIFY_EMAIL = "info@mattsmok.art";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  let payload: { record?: { email?: string; created_at?: string } };
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const email = payload.record?.email ?? "nieznany email";
  const verifiedAt = payload.record?.created_at ?? new Date().toISOString();

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "Spotigraj <info@spotigraj.app>",
      to: [NOTIFY_EMAIL],
      subject: "Użytkownik zweryfikował konto w Spotigraj",
      text: `Użytkownik potwierdził rejestrację w Spotigraj klikając link weryfikacyjny.\n\nEmail: ${email}\nZweryfikowano: ${verifiedAt}`,
    }),
  });

  if (!res.ok) {
    console.error("Resend error:", await res.text());
    return new Response("Email send failed", { status: 502 });
  }

  return new Response("ok", { status: 200 });
});
