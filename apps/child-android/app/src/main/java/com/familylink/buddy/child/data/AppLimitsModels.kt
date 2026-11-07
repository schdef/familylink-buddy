package com.familylink.buddy.child.data

import org.json.JSONArray
import org.json.JSONObject

data class CategoryConfig(
    val id: String,
    val name: String,
    val dailyMinutes: Int,
    val packages: Set<String> = emptySet(),
    val icon: String? = null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "dailyMinutes" to dailyMinutes,
        "dailyLimitMinutes" to dailyMinutes,
        "packages" to packages.toList(),
        "icon" to icon
    )

    fun toJsonObject(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("dailyMinutes", dailyMinutes)
        put("dailyLimitMinutes", dailyMinutes)
        if (icon != null) put("icon", icon)
        val pkgsArray = JSONArray()
        packages.forEach { pkgsArray.put(it) }
        put("packages", pkgsArray)
    }

    companion object {
        fun fromMap(map: Map<String, Any?>): CategoryConfig {
            val id = (map["id"] as? String) ?: ""
            val name = (map["name"] as? String) ?: id
            val dailyMinutes = (map["dailyMinutes"] as? Number)?.toInt()
                ?: (map["dailyLimitMinutes"] as? Number)?.toInt()
                ?: 0
            val rawPkgs = (map["packages"] as? List<*>) ?: emptyList<Any>()
            val packages = rawPkgs.mapNotNull { it?.toString() }.toSet()
            val icon = map["icon"] as? String
            return CategoryConfig(id, name, dailyMinutes, packages, icon)
        }

        fun fromJsonObject(json: JSONObject): CategoryConfig {
            val id = json.optString("id", "")
            val name = json.optString("name", id)
            val dailyMinutes = if (json.has("dailyLimitMinutes")) {
                json.optInt("dailyLimitMinutes", 0)
            } else {
                json.optInt("dailyMinutes", 0)
            }
            val icon = if (json.has("icon") && !json.isNull("icon")) json.optString("icon") else null
            val pkgs = mutableSetOf<String>()
            val pkgsArray = json.optJSONArray("packages")
            if (pkgsArray != null) {
                for (j in 0 until pkgsArray.length()) {
                    pkgs.add(pkgsArray.getString(j))
                }
            }
            return CategoryConfig(id, name, dailyMinutes, pkgs, icon)
        }
    }
}

data class AppRules(
    val blacklistedPackages: Set<String> = emptySet(),
    val categories: List<CategoryConfig> = emptyList(),
    val bonusMinutes: Map<String, Int> = emptyMap()
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "blacklistedPackages" to blacklistedPackages.toList(),
        "categories" to categories.map { it.toMap() },
        "bonusMinutes" to bonusMinutes
    )

    fun toJson(): String {
        val json = JSONObject()
        val blArray = JSONArray()
        blacklistedPackages.forEach { blArray.put(it) }
        json.put("blacklistedPackages", blArray)

        val catArray = JSONArray()
        categories.forEach { cat ->
            catArray.put(cat.toJsonObject())
        }
        json.put("categories", catArray)

        val bonusObj = JSONObject()
        bonusMinutes.forEach { (k, v) -> bonusObj.put(k, v) }
        json.put("bonusMinutes", bonusObj)

        return json.toString()
    }

    companion object {
        fun fromMap(map: Map<String, Any?>): AppRules {
            val rawBlacklist = (map["blacklistedPackages"] as? List<*>) ?: emptyList<Any>()
            val blacklisted = rawBlacklist.mapNotNull { it?.toString() }.toSet()

            val rawCats = (map["categories"] as? List<*>) ?: emptyList<Any>()
            val categories = rawCats.mapNotNull {
                when (it) {
                    is Map<*, *> -> {
                        @Suppress("UNCHECKED_CAST")
                        CategoryConfig.fromMap(it as Map<String, Any?>)
                    }
                    else -> null
                }
            }

            val rawBonus = (map["bonusMinutes"] as? Map<*, *>) ?: emptyMap<Any, Any>()
            val bonusMap = mutableMapOf<String, Int>()
            rawBonus.forEach { (k, v) ->
                val catId = k?.toString() ?: return@forEach
                val minutes = (v as? Number)?.toInt() ?: v?.toString()?.toIntOrNull() ?: 0
                bonusMap[catId] = minutes
            }

            return AppRules(blacklisted, categories, bonusMap)
        }

        fun fromJson(jsonStr: String): AppRules {
            if (jsonStr.isBlank()) return AppRules()
            return try {
                val json = JSONObject(jsonStr)
                val blacklisted = mutableSetOf<String>()
                val blArray = json.optJSONArray("blacklistedPackages")
                if (blArray != null) {
                    for (i in 0 until blArray.length()) {
                        blacklisted.add(blArray.getString(i))
                    }
                }

                val categories = mutableListOf<CategoryConfig>()
                val catArray = json.optJSONArray("categories")
                if (catArray != null) {
                    for (i in 0 until catArray.length()) {
                        val obj = catArray.getJSONObject(i)
                        categories.add(CategoryConfig.fromJsonObject(obj))
                    }
                }

                val bonusMinutes = mutableMapOf<String, Int>()
                val bonusObj = json.optJSONObject("bonusMinutes")
                if (bonusObj != null) {
                    val keys = bonusObj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        bonusMinutes[k] = bonusObj.optInt(k, 0)
                    }
                }

                AppRules(blacklisted, categories, bonusMinutes)
            } catch (e: Exception) {
                AppRules()
            }
        }
    }
}

sealed class AppInterceptionResult {
    object None : AppInterceptionResult()
    data class Allowed(val activeCategoryId: String?) : AppInterceptionResult()
    data class BlockedBlacklist(
        val packageName: String,
        val appName: String,
        val message: String = "$appName ist auf diesem Tablet gesperrt"
    ) : AppInterceptionResult()
    data class BlockedCategoryLimit(
        val categoryId: String,
        val categoryName: String,
        val message: String = "Zeitlimit für '$categoryName' heute aufgebraucht"
    ) : AppInterceptionResult()
}
