import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const IP_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

async function hashIp(ip: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extractClientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1. Uwierzytelnienie: kto woła? JWT jest źródłem prawdy dla new_user_id,
  //    nie ufamy w tym zakresie samemu body (ktoś mógłby podstawić cudze id).
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Brak autoryzacji" }, 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "Nieprawidłowa sesja" }, 401);
  const newUserId = userData.user.id;

  let body: { short_id?: string; new_user_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Nieprawidłowe dane wejściowe" }, 400);
  }
  const shortId = typeof body?.short_id === "string" ? body.short_id.trim() : "";
  if (!shortId) return json({ error: "Brak short_id" }, 400);

  if (body.new_user_id && body.new_user_id !== newUserId) {
    console.warn(`resolve-referral: new_user_id z body (${body.new_user_id}) != JWT (${newUserId}), używam JWT`);
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 2. Znajdź referrera po short_id. Brak linku nie jest błędem — po prostu
  //    nikt nie polecił tego usera, rejestracja ma iść dalej bez przeszkód.
  const { data: link, error: linkErr } = await admin
    .from("referral_links")
    .select("referrer_id, click_count")
    .eq("short_id", shortId)
    .maybeSingle();

  if (linkErr) {
    console.error("resolve-referral: błąd odczytu referral_links:", linkErr);
    return json({ success: true, outcome: "error", message: "Błąd odczytu linku polecającego." });
  }
  if (!link) {
    return json({ success: true, outcome: "no_such_link", message: "Nie znaleziono linku polecającego — pomijam." });
  }

  const referrerId = link.referrer_id as string;

  // 3. Samo-polecenie — czytelny komunikat zamiast surowego błędu z CHECK w bazie.
  if (referrerId === newUserId) {
    return json({ success: true, outcome: "self_referral", message: "Nie można polecić samego siebie — pomijam." });
  }

  // 4. Idempotentność — user już ma przypisany referral (np. funkcja wywołana dwa razy).
  const { data: existingReferral } = await admin
    .from("referrals")
    .select("id")
    .eq("referred_user_id", newUserId)
    .maybeSingle();

  if (existingReferral) {
    return json({ success: true, outcome: "already_referred", message: "Ten użytkownik ma już przypisany referral." });
  }

  // 5. Anty-fraud: ten sam ip_hash w ostatnich 24h -> pomiń przypisanie referrala,
  //    ale NIE blokuj samej rejestracji usera w profiles.
  const clientIp = extractClientIp(req);
  const ipHash = clientIp ? await hashIp(clientIp) : null;

  if (ipHash) {
    const since = new Date(Date.now() - IP_LIMIT_WINDOW_MS).toISOString();
    const { count, error: ipCheckErr } = await admin
      .from("referrals")
      .select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash)
      .gte("created_at", since);

    if (ipCheckErr) {
      console.error("resolve-referral: błąd sprawdzania ip_hash:", ipCheckErr);
    } else if (count && count > 0) {
      return json({
        success: true,
        outcome: "ip_limit_reached",
        message: "Osiągnięto limit rejestracji z tego adresu IP w ciągu 24h — pomijam przypisanie referrala.",
      });
    }
  }

  // 6. Zapis referrala. Funkcja jest wywoływana dopiero PO potwierdzeniu emaila,
  //    więc w tym momencie email jest z definicji zweryfikowany — email_verified_at
  //    ustawiamy od razu. Pozostałe warunki aktywności (profil, relogin, akcja)
  //    zostają null i będą uzupełniane przez osobny mechanizm (cron, Krok 7).
  const { error: insertErr } = await admin.from("referrals").insert({
    referrer_id: referrerId,
    referred_user_id: newUserId,
    status: "pending",
    ip_hash: ipHash,
    email_verified_at: new Date().toISOString(),
  });

  if (insertErr) {
    // 23505 = unique_violation na referred_user_id — równoległe wywołanie już wstawiło wiersz.
    if (insertErr.code === "23505") {
      return json({ success: true, outcome: "already_referred", message: "Referral już istnieje (równoległe wywołanie)." });
    }
    console.error("resolve-referral: błąd zapisu referrala:", insertErr);
    return json({ success: true, outcome: "error", message: "Nie udało się zapisać referrala." });
  }

  // 7. click_count — tylko do trackingu, best-effort, nie wpływa na wynik funkcji.
  const { error: clickErr } = await admin
    .from("referral_links")
    .update({ click_count: (link.click_count ?? 0) + 1 })
    .eq("short_id", shortId);
  if (clickErr) console.error("resolve-referral: błąd inkrementacji click_count:", clickErr);

  // 8. Upewnij się, że referrer ma wiersz w referral_credits.
  const { error: creditsErr } = await admin
    .from("referral_credits")
    .upsert({ user_id: referrerId }, { onConflict: "user_id", ignoreDuplicates: true });
  if (creditsErr) console.error("resolve-referral: błąd upsertu referral_credits:", creditsErr);

  return json({ success: true, outcome: "assigned", message: "Referral przypisany.", referrer_id: referrerId });
});
