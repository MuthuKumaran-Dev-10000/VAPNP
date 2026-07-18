package com.razorpay;

public interface EventCallback {
    void onEvent(String payloadJson);
}
