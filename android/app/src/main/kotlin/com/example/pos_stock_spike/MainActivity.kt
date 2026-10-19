package com.example.pos_stock_spike

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (no FlutterActivity) porque local_auth necesita un
// FragmentActivity para mostrar el prompt biométrico nativo de Android.
class MainActivity : FlutterFragmentActivity()
