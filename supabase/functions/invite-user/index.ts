import { createClient } from 'npm:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const { email } = await req.json()
  if (!email) {
    return new Response(JSON.stringify({ error: 'Falta email' }), { status: 400 })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const { error } = await admin.auth.admin.inviteUserByEmail(email)
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
  return new Response(JSON.stringify({ ok: true }), { status: 200 })
})
