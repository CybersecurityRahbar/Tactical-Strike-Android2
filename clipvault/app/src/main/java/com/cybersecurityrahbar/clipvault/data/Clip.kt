package com.cybersecurityrahbar.clipvault.data

data class Clip(
    val id: Long,
    val text: String,
    val hash: String,
    val copiedAt: Long,
    val pinned: Boolean,
    val source: String
)
