# Keep Razorpay SDK classes intact
-keep class com.razorpay.** {*;}
-dontwarn com.razorpay.**

# Keep Webview and JavascriptInterface methods
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*

# Keep payment callback methods
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
