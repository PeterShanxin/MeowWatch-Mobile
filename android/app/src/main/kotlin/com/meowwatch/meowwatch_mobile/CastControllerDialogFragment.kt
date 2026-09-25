package com.meowwatch.meowwatch_mobile

import android.content.Context
import android.os.Bundle
import androidx.annotation.Keep
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteControllerDialog
import androidx.mediarouter.app.MediaRouteControllerDialogFragment

@Keep
class CastControllerDialogFragment : MediaRouteControllerDialogFragment() {
    override fun onCreateControllerDialog(context: Context, savedInstanceState: Bundle?): MediaRouteControllerDialog =
        MediaRouteControllerDialog(ContextThemeWrapper(context, androidx.appcompat.R.style.Theme_AppCompat_DayNight))
}
