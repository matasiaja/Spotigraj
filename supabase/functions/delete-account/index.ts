import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Brak autoryzacji' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

  // Klient do identyfikacji wywolujacego na podstawie jego JWT
  const supabaseAuth = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  })

  const { data: { user }, error: userError } = await supabaseAuth.auth.getUser()
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Nieprawidlowa sesja' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  const admin = createClient(supabaseUrl, serviceRoleKey)

  const userId = user.id
  const userEmail = user.email

  try {
    // 1. Kasujemy premium_test_feedback (FK NO ACTION zablokowalby deleteUser)
    await admin.from('premium_test_feedback').delete().eq('user_id', userId)

    // 2. Kasujemy premium_test_signups po emailu (brak FK do auth.users)
    if (userEmail) {
      await admin.from('premium_test_signups').delete().eq('email', userEmail)
    }

    // 3. Kasujemy bug_reports w calosci (zamiast domyslnego SET NULL)
    await admin.from('bug_reports').delete().eq('user_id', userId)

    // 4. Kasujemy konto - profiles/matches/messages/push_subscriptions/changelog_reads
    //    leca kaskadowo (ON DELETE CASCADE)
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId)

    if (deleteError) {
      return new Response(JSON.stringify({ error: deleteError.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
