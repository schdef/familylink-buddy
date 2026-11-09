package com.familylink.buddy.child.data

/**
 * Validates and manages parent PIN verification for child app settings and anti-tamper protection.
 */
object ParentPinManager {

    /**
     * Checks if a string is a valid 4-digit numeric PIN format.
     */
    fun isValidPinFormat(pin: String?): Boolean {
        if (pin == null) return false
        return pin.length == 4 && pin.all { it.isDigit() }
    }

    /**
     * Verifies if the entered PIN matches the configured PIN.
     * If no PIN is configured (null or blank), any access is considered valid.
     */
    fun verifyPin(enteredPin: String, configuredPin: String?): Boolean {
        if (configuredPin.isNullOrBlank()) {
            return true
        }
        return enteredPin == configuredPin
    }
}
