package app.family.family_utility_app

import android.content.Context
import android.os.ParcelFileDescriptor
import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * 017 Print to PDF: a printer called "Save as PDF (Family)" in every app's
 * print dialog. The print framework hands this service the job as a PDF; it is
 * copied into the app's own files (`app_flutter/printed`, the folder Dart's
 * getApplicationDocumentsDirectory points at) and never leaves the phone.
 */
class PdfPrintService : PrintService() {
    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession = FamilyPdfDiscovery(this)

    override fun onRequestCancelPrintJob(printJob: PrintJob) {
        if (!printJob.isCompleted && !printJob.isCancelled) {
            printJob.cancel()
        }
    }

    override fun onPrintJobQueued(printJob: PrintJob) {
        if (!printJob.isQueued) {
            return
        }
        printJob.start()
        val data: ParcelFileDescriptor? = printJob.document.data
        if (data == null) {
            printJob.fail("The app sent nothing to print.")
            return
        }
        try {
            val dir = File(getDir("flutter", Context.MODE_PRIVATE), FOLDER)
            dir.mkdirs()
            val name = uniqueName(dir, fileName(printJob.info.label))
            val part = File(dir, name + PART)
            data.use { pfd ->
                FileInputStream(pfd.fileDescriptor).use { input ->
                    FileOutputStream(part).use { output -> input.copyTo(output) }
                }
            }
            if (part.renameTo(File(dir, name))) {
                printJob.complete()
            } else {
                part.delete()
                printJob.fail("Could not save the PDF.")
            }
        } catch (e: Exception) {
            printJob.fail(e.message ?: "Could not save the PDF.")
        }
    }

    companion object {
        const val FOLDER = "printed"
        const val PART = ".part"
        const val PRINTER_NAME = "Save as PDF (Family)"

        /** Same rule as PrintToPdfNames.fileName in Dart. */
        fun fileName(label: String?): String {
            var base = (label ?: "").replace(Regex("[^A-Za-z0-9 ._-]"), " ")
            base = base.replace(Regex("\\s+"), " ").trim()
            if (base.lowercase().endsWith(".pdf")) {
                base = base.substring(0, base.length - 4).trim()
            }
            base = base.trimStart('.', ' ')
            if (base.length > 60) {
                base = base.substring(0, 60).trim()
            }
            if (base.isEmpty()) {
                base = "Printed"
            }
            return "$base.pdf"
        }

        fun uniqueName(dir: File, name: String): String {
            if (!File(dir, name).exists()) {
                return name
            }
            val stem = name.substring(0, name.length - 4)
            var i = 2
            while (File(dir, "$stem ($i).pdf").exists()) {
                i++
            }
            return "$stem ($i).pdf"
        }
    }
}

private class FamilyPdfDiscovery(private val service: PdfPrintService) : PrinterDiscoverySession() {
    override fun onStartPrinterDiscovery(priorityList: List<PrinterId>) {
        val id = service.generatePrinterId("family-pdf")
        val caps = PrinterCapabilitiesInfo.Builder(id)
            .addMediaSize(PrintAttributes.MediaSize.ISO_A4, true)
            .addMediaSize(PrintAttributes.MediaSize.NA_LETTER, false)
            .addMediaSize(PrintAttributes.MediaSize.NA_LEGAL, false)
            .addMediaSize(PrintAttributes.MediaSize.ISO_A5, false)
            .addMediaSize(PrintAttributes.MediaSize.ISO_A3, false)
            .addResolution(PrintAttributes.Resolution("r300", "300 dpi", 300, 300), true)
            .setColorModes(
                PrintAttributes.COLOR_MODE_COLOR or PrintAttributes.COLOR_MODE_MONOCHROME,
                PrintAttributes.COLOR_MODE_COLOR,
            )
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .build()
        val printer = PrinterInfo.Builder(id, PdfPrintService.PRINTER_NAME, PrinterInfo.STATUS_IDLE)
            .setCapabilities(caps)
            .build()
        addPrinters(listOf(printer))
    }

    override fun onStopPrinterDiscovery() {}

    override fun onValidatePrinters(printerIds: List<PrinterId>) {}

    override fun onStartPrinterStateTracking(printerId: PrinterId) {}

    override fun onStopPrinterStateTracking(printerId: PrinterId) {}

    override fun onDestroy() {}
}
