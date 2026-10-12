package android.print

import android.os.Build
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import java.io.File

class NativePdfPrinter(private val printAttributes: PrintAttributes) {

    interface Callback {
        fun onSuccess(filePath: String)
        fun onFailure(error: String?)
    }

    fun print(
        printAdapter: PrintDocumentAdapter,
        outputFile: File,
        callback: Callback
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            printAdapter.onLayout(
                null,
                printAttributes,
                null,
                object : PrintDocumentAdapter.LayoutResultCallback() {
                    override fun onLayoutFinished(info: PrintDocumentInfo?, changed: Boolean) {
                        try {
                            outputFile.parentFile?.mkdirs()
                            if (outputFile.exists()) {
                                outputFile.delete()
                            }
                            val pfd = ParcelFileDescriptor.open(outputFile, ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE)

                            // Only print page 0 (single continuous page per thread page)
                            // to eliminate any accidental trailing blank overflow pages
                            printAdapter.onWrite(
                                arrayOf(PageRange(0, 0)),
                                pfd,
                                CancellationSignal(),
                                object : PrintDocumentAdapter.WriteResultCallback() {
                                    override fun onWriteFinished(pages: Array<out PageRange>?) {
                                        super.onWriteFinished(pages)
                                        try {
                                            pfd.close()
                                        } catch (_: Exception) {}
                                        callback.onSuccess(outputFile.absolutePath)
                                    }

                                    override fun onWriteFailed(error: CharSequence?) {
                                        super.onWriteFailed(error)
                                        try {
                                            pfd.close()
                                        } catch (_: Exception) {}
                                        callback.onFailure(error?.toString())
                                    }

                                    override fun onWriteCancelled() {
                                        super.onWriteCancelled()
                                        try {
                                            pfd.close()
                                        } catch (_: Exception) {}
                                        callback.onFailure("Cancelled")
                                    }
                                }
                            )
                        } catch (e: Exception) {
                            callback.onFailure(e.message)
                        }
                    }

                    override fun onLayoutFailed(error: CharSequence?) {
                        super.onLayoutFailed(error)
                        callback.onFailure(error?.toString())
                    }
                },
                null
            )
        } else {
            callback.onFailure("Requires KITKAT+")
        }
    }
}
