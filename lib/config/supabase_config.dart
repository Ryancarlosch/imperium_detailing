class SupabaseConfig {
  const SupabaseConfig._();

  static const String projectUrl = String.fromEnvironment(
    'IMPERIUM_SUPABASE_URL',
    defaultValue: 'https://tiztkfiqkrpfzuwswmfz.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'IMPERIUM_SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_q-1FDqL_qQho40Fgfm0__Q_Stl_z2PS',
  );

  static bool get configurado {
    return projectUrl.startsWith('https://') &&
        projectUrl.endsWith('.supabase.co') &&
        publishableKey.startsWith('sb_publishable_');
  }
}
