import SwiftUI

/// Bandeja de entrada: correos sin leer, el mas reciente arriba. Al pulsar uno se
/// abre en su app.
struct MailView: View {
    let mail: MailService

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, NotchContentView.margin)
                .frame(height: NotchMetrics.searchRowHeight - 10)
                .padding(.bottom, 10)
            content
                .padding(.horizontal, NotchContentView.margin)
                .frame(height: NotchMetrics.cardRowHeight, alignment: .top)
        }
        .onAppear { mail.refresh() }
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
                Text(mail.messages.isEmpty ? String(localized: "Todo leído") : String(localized: "\(mail.messages.count) sin leer"))
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
                        MailRow(message: message) { mail.open(message) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 8)
                .animation(AppMotion.snappy, value: mail.messages)
            }
        case .ok:
            notice(icon: "checkmark.circle.fill", title: "No tienes correos sin leer")
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
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Text(verbatim: initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.onAccent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppColors.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: message.sender)
                        .font(AppTypography.cardTitle.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: message.subject.isEmpty ? String(localized: "(Sin asunto)") : message.subject)
                        .font(AppTypography.cardCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: time)
                    .font(AppTypography.cardCaption.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hovering ? AppColors.accent : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Abrir el correo"))
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
