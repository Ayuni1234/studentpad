import 'package:supabase_flutter/supabase_flutter.dart';

/// Public client settings for StudentPad's Supabase project.
/// Build-time values can override these defaults for another environment.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://jpnuhdqcfmjrmkvxsuvo.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpwbnVoZHFjZm1qcm1rdnhzdXZvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTYzMjMsImV4cCI6MjEwNjYzMjMyM30.Jv9RRCn-qEOtsAQZ2mvCKzZMpPvQnF6N247MGwxsgDI',
);

bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

SupabaseClient get supabase => Supabase.instance.client;
