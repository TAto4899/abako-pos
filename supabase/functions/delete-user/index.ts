import { createClient } from 'npm:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const { userId } = await req.json()
  if (!userId) {
    return new Response(JSON.stringify({ error: 'Falta userId' }), { status: 400 })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // perfiles.id referencia auth.users(id) sin ON DELETE CASCADE — hay que
  // borrar el perfil primero o el borrado del usuario de auth falla por la
  // foreign key.
  await admin.from('perfiles').delete().eq('id', userId)

  const { error } = await admin.auth.admin.deleteUser(userId)
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
  return new Response(JSON.stringify({ ok: true }), { status: 200 })
})
