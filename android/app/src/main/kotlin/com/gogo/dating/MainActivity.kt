package com.gogo.dating

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.gogo.app/phone_hint"
    private var pendingResult: MethodChannel.Result? = null
    private val REQUEST_CODE_PHONE_HINT = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots and hide content in Recent Apps (App Switcher)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "showPhoneHint") {
                pendingResult = result
                showPhoneHint()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun showPhoneHint() {
        val request: GetPhoneNumberHintIntentRequest = GetPhoneNumberHintIntentRequest.builder().build()

        Identity.getSignInClient(this)
            .getPhoneNumberHintIntent(request)
            .addOnSuccessListener { result ->
                try {
                    startIntentSenderForResult(
                        result.intentSender,
                        REQUEST_CODE_PHONE_HINT,
                        null,
                        0,
                        0,
                        0
                    )
                } catch (e: IntentSender.SendIntentException) {
                    pendingResult?.error("ERROR", "Failed to send intent", e.message)
                    pendingResult = null
                }
            }
            .addOnFailureListener { e ->
                pendingResult?.error("ERROR", "Failed to get phone number hint intent", e.message)
                pendingResult = null
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PHONE_HINT) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    val phoneNumber = Identity.getSignInClient(this).getPhoneNumberFromIntent(data)
                    pendingResult?.success(phoneNumber)
                } catch (e: Exception) {
                    pendingResult?.error("ERROR", "Failed to extract phone number", e.message)
                }
            } else {
                pendingResult?.error("CANCELLED", "User cancelled or failed", null)
            }
            pendingResult = null
        }
    }
}
