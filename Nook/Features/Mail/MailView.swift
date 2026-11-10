import SwiftUI

/// Bandeja de entrada: los ultimos correos, el mas reciente arriba, con el principio
/// del texto. Los sin leer llevan punto azul y el remitente en negrita. Al pulsar uno se lee aqui mismo; desde ahi se responde, se marca como
/// leido o se abre en su app.
struct MailView: View {
    let mail: MailService
    @State private var reading: MailService.Message?

    var body: some View {
        VStack(spacing: 0) {
            if let reading {
                MailReader(mail: mail, message: reading) {
                    withAnimation(AppMotion.snappy) { self.reading = nil }
                }
                .padding(.horizontal, NotchContentView.margin)
                .frame(height: NotchMetrics.searchRowHeight + NotchMetrics.cardRowHeight + NotchMetrics.readerExtra, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Group {
                    header
                        .padding(.horizontal, NotchContentView.margin)
                        .frame(height: NotchMetrics.searchRowHeight - 10)
                        .padding(.bottom, 10)
                    content
                        .padding(.horizontal, NotchContentView.margin)
                        .frame(height: NotchMetrics.cardRowHeight + NotchMetrics.readerExtra, alignment: .top)
                        .overlay(alignment: .bottom) { undoBar }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear { mail.refresh() }
        .animation(AppMotion.snappy, value: mail.pendingTrash)
    }

    /// "Movido a la papelera · Deshacer" mientras se puede deshacer.
    @ViewBuilder
    private var undoBar: some View {
        if mail.pendingTrash != nil {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(AppColors.textSecondary)
                Text("Movido a la papelera")
                    .foregroundStyle(AppColors.textPrimary)
                Button {
                    withAnimation(AppMotion.snappy) { mail.undoTrash() }
                } label: {
                    Text("Deshacer").foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
            .font(AppTypography.bodyStrong)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(AppColors.floating))
            .overlay(Capsule().strokeBorder(AppColors.textPrimary.opacity(0.12), lineWidth: 1))
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let logo = AgentIcons.mail(mail.source) {
                Image(nsImage: logo).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "tray.full.fill").foregroundStyle(AppColors.accent)
            }
            Text(mail.source == .mail ? "Mail" : "Outlook")
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.textPrimary)
            if mail.state == .ok {
                Text(mail.unreadCount == 0 ? String(localized: "Todo leído") : String(localized: "\(mail.unreadCount) sin leer"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Button { mail.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Actualizar"))
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .liquidGlass(in: Capsule())
    }

    @ViewBuilder
    private var content: some View {
        switch mail.state {
        case .ok where !mail.messages.isEmpty:
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(mail.messages) { message in
                        MailRow(message: message, mail: mail) {
                            withAnimation(AppMotion.snappy) { reading = message }
                        }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 8)
                .animation(AppMotion.snappy, value: mail.messages)
            }
        case .ok:
            notice(icon: "checkmark.circle.fill", title: "No hay correos en la bandeja")
        case .notRunning, .idle:
            notice(icon: "envelope", title: mail.source == .mail ? "Mail no está abierto" : "Outlook no está abierto",
                   action: (String(localized: "Abrir en segundo plano"), mail.launchSource))
        case .denied:
            notice(icon: "lock.fill", title: "Nook necesita permiso para leer la bandeja",
                   action: (String(localized: "Permitir en Ajustes del Sistema…"), mail.openPrivacySettings))
        case .unsupported:
            notice(icon: "exclamationmark.triangle.fill",
                   title: mail.source == .outlook ? "Este Outlook no deja leer el correo (usa el clásico o Mail)" : "Mail no responde")
        }
    }

    private func notice(icon: String, title: LocalizedStringKey, action: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            Text(title)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: action.1) {
                    Text(verbatim: action.0)
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
    }
}

private struct MailRow: View {
    let message: MailService.Message
    let mail: MailService
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Text(verbatim: initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(message.isRead ? AppColors.textSecondary : AppColors.onAccent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(message.isRead ? AppColors.controlTrack : AppColors.accent))
                    .overlay(alignment: .topLeading) {
                        if !message.isRead {
                            Circle().fill(AppColors.accent)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(AppColors.panel, lineWidth: 1.5))
                                .offset(x: -3, y: -2)
                        }
                    }
                    .accessibilityLabel(Text(message.isRead ? "Leído" : "Sin leer"))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(verbatim: message.sender)
                            .font(AppTypography.cardTitle.weight(message.isRead ? .regular : .semibold))
                            .foregroundStyle(message.isRead ? AppColors.textSecondary : AppColors.textPrimary)
                        Spacer(minLength: 8)
                        Text(verbatim: time)
                            .font(AppTypography.cardCaption.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Text(verbatim: message.subject.isEmpty ? String(localized: "(Sin asunto)") : message.subject)
                        .font(AppTypography.cardCaption.weight(message.isRead ? .regular : .medium))
                        .foregroundStyle(message.isRead ? AppColors.textSecondary : AppColors.textPrimary.opacity(0.9))
                    if !message.preview.isEmpty {
                        Text(verbatim: message.preview)
                            .font(AppTypography.cardCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .lineLimit(1)
                // Con el raton encima, el texto deja sitio a los botones en vez de quedar debajo.
                .padding(.trailing, hovering ? (message.isRead ? 36 : 68) : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hovering ? AppColors.accent : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Leer el correo"))
        // Acciones rapidas sin abrir el correo (fuera del boton de la fila, para
        // que cada una reciba su propio clic).
        .overlay(alignment: .trailing) {
            if hovering {
                HStack(spacing: 4) {
                    if !message.isRead {
                        ReaderButton(icon: "envelope.open.fill", help: "Marcar como leído") { mail.markRead(message) }
                    }
                    ReaderButton(icon: "trash.fill", help: "Mover a la papelera") { mail.trash(message) }
                }
                .padding(.trailing, 8)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
    }

    private var initials: String {
        let words = message.sender.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    /// Hora si es de hoy; si no, el dia.
    private var time: String {
        Calendar.current.isDateInToday(message.date)
            ? message.date.formatted(date: .omitted, time: .shortened)
            : message.date.formatted(.dateTime.day().month(.abbreviated))
    }
}


/// Un correo abierto dentro del notch.
private struct MailReader: View {
    let mail: MailService
    let message: MailService.Message
    let back: () -> Void
    @State private var detail: MailService.Detail?
    @State private var html: String?
    @State private var allowRemote = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text("Volver"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: detail?.sender.isEmpty == false ? detail!.sender : message.sender)
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColors.textPrimary)
                    if let address = detail?.address, !address.isEmpty {
                        Text(verbatim: address)
                            .font(AppTypography.cardCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.cardCaption)
                    .foregroundStyle(AppColors.textSecondary)
                actions
            }

            Text(verbatim: message.subject.isEmpty ? String(localized: "(Sin asunto)") : message.subject)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Group {
                if let html {
                    MailHTMLView(html: html, allowRemote: allowRemote)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if !allowRemote, html.range(of: "src=[\"']?https?:", options: .regularExpression) != nil {
                                Button("Cargar imágenes") { allowRemote = true }
                                    .controlSize(.small)
                                    .padding(8)
                            }
                        }
                } else if let detail {
                    ScrollView(.vertical) {
                        Text(verbatim: detail.body.isEmpty ? String(localized: "(Sin texto)") : detail.body)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else if failed {
                    Text("No he podido leer este correo a tiempo. Ábrelo en su app con el botón de la flecha.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 8)
        }
        .task(id: message.id) {
            detail = nil
            html = nil
            allowRemote = false
            failed = false
            // Primero el texto (rapido); luego, si lo tiene, el HTML.
            detail = await mail.detail(of: message)
            failed = detail == nil
            html = await mail.html(of: message)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ReaderButton(icon: "arrowshape.turn.up.left.fill", help: "Responder") { mail.reply(to: message) }
            ReaderButton(icon: "envelope.open.fill", help: "Marcar como leído") {
                mail.markRead(message)
                back()
            }
            ReaderButton(icon: "trash.fill", help: "Mover a la papelera") {
                mail.trash(message)
                back()
            }
            ReaderButton(icon: "arrow.up.forward.app.fill", help: "Abrir en la app") { mail.open(message) }
        }
    }
}

private struct ReaderButton: View {
    let icon: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.85))
                .frame(width: 28, height: 28)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}
