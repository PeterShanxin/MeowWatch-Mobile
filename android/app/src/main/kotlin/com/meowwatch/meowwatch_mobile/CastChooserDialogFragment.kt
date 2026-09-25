package com.meowwatch.meowwatch_mobile

import android.content.Context
import android.content.DialogInterface
import android.os.Bundle
import androidx.annotation.Keep
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteChooserDialogFragment

/** Public no-argument fragment so Android can restore the standard Cast chooser. */
@Keep
class CastChooserDialogFragment : MediaRouteChooserDialogFragment() {
    override fun onCreateChooserDialog(context: Context, savedInstanceState: Bundle?): MediaRouteChooserDialog =
        MediaRouteChooserDialog(ContextThemeWrapper(context, androidx.appcompat.R.style.Theme_AppCompat_DayNight))

    override fun onCancel(dialog: DialogInterface) {
        super.onCancel(dialog)
        parentFragmentManager.setFragmentResult("meowwatch_cast_cancelled", Bundle())
    }
}
