package com.cybersecurityrahbar.clipvault.ui

import android.content.res.ColorStateList
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.Clip
import com.cybersecurityrahbar.clipvault.util.TimeUtil

class ClipAdapter(
    private val onCopy: (Clip) -> Unit,
    private val onPin: (Clip) -> Unit,
    private val onShare: (Clip) -> Unit,
    private val onDelete: (Clip) -> Unit
) : RecyclerView.Adapter<ClipAdapter.Holder>() {

    private val items = ArrayList<Clip>()
    private val expanded = HashSet<Long>()

    fun submit(list: List<Clip>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    override fun getItemCount(): Int = items.size

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder =
        Holder(LayoutInflater.from(parent.context).inflate(R.layout.item_clip, parent, false))

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val clip = items[position]
        val context = holder.itemView.context
        val isExpanded = expanded.contains(clip.id)

        holder.text.text = clip.text
        holder.text.maxLines = if (isExpanded) Int.MAX_VALUE else 8
        holder.text.ellipsize = if (isExpanded) null else android.text.TextUtils.TruncateAt.END
        holder.text.setOnClickListener {
            if (isExpanded) expanded.remove(clip.id) else expanded.add(clip.id)
            val current = holder.bindingAdapterPosition
            if (current != RecyclerView.NO_POSITION) notifyItemChanged(current)
        }

        val pinnedLabel = if (clip.pinned) "  •  " + context.getString(R.string.pinned_badge) else ""
        holder.time.text = TimeUtil.dateTime(clip.copiedAt) + pinnedLabel

        val tint = if (clip.pinned) R.color.accent else R.color.text_secondary
        holder.pin.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(context, tint))
        holder.copy.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(context, R.color.text_secondary))
        holder.share.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(context, R.color.text_secondary))
        holder.delete.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(context, R.color.text_secondary))

        holder.pin.contentDescription = context.getString(if (clip.pinned) R.string.unpin else R.string.pin)
        holder.pin.setOnClickListener { onPin(clip) }
        holder.copy.setOnClickListener { onCopy(clip) }
        holder.share.setOnClickListener { onShare(clip) }
        holder.delete.setOnClickListener { onDelete(clip) }
    }

    class Holder(view: View) : RecyclerView.ViewHolder(view) {
        val text: TextView = view.findViewById(R.id.clip_text)
        val time: TextView = view.findViewById(R.id.clip_time)
        val pin: ImageButton = view.findViewById(R.id.btn_pin)
        val copy: ImageButton = view.findViewById(R.id.btn_copy)
        val share: ImageButton = view.findViewById(R.id.btn_share)
        val delete: ImageButton = view.findViewById(R.id.btn_delete)
    }
}
