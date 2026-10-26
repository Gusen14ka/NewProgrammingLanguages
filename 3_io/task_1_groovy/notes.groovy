import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class Note {
    String created
    List<String> tags
    String text

    String serialize() { "${created}|${tags.join(',')}|${text}" }

    static Note parse(String line) {
        def parts = line.split(/\|/, 3)
        new Note(created: parts[0],
                 tags: parts[1] ? parts[1].split(',').toList() : [],
                 text: parts[2])
    }
}

def file = new File(args ? args[0] : 'notes.txt')
List<Note> notes = file.exists() ? file.readLines().findAll { it }.collect { Note.parse(it) } : []
def save = { file.text = notes.collect { it.serialize() + '\n' }.join() }
def fmt = DateTimeFormatter.ofPattern('yyyy-MM-dd HH:mm')
def show = { int i, Note n ->
    def tags = n.tags ? '  [' + n.tags.collect { '#' + it }.join(' ') + ']' : ''
    println "${i + 1}. (${n.created}) ${n.text}${tags}"
}

println "Notes file: ${file.path}, loaded ${notes.size()} note(s)"
println 'Commands: add <text> #tag ... | list | search <word> | remove <number> | help | exit'

def input = new BufferedReader(new InputStreamReader(System.in))
while (true) {
    print '> '
    System.out.flush()
    def line = input.readLine()
    if (line == null) break
    line = line.trim()
    if (!line) continue

    def (cmd, rest) = line.contains(' ') ? [line[0..<line.indexOf(' ')], line[line.indexOf(' ') + 1..-1].trim()] : [line, '']

    switch (cmd) {
        case 'add':
            def words = rest.split(/\s+/).toList()
            def tags = words.findAll { it.startsWith('#') && it.size() > 1 }.collect { it.substring(1) }
            def text = words.findAll { !(it.startsWith('#') && it.size() > 1) }.join(' ')
            if (!text) { println 'Error: note text is empty'; break }
            notes << new Note(created: LocalDateTime.now().format(fmt), tags: tags, text: text)
            save()
            println "Added note #${notes.size()}"
            break
        case 'list':
            if (!notes) println 'No notes yet'
            notes.eachWithIndex { n, i -> show(i, n) }
            break
        case 'search':
            if (!rest) { println 'Error: search needs a word'; break }
            def word = rest.toLowerCase()
            def found = 0
            notes.eachWithIndex { n, i ->
                if (n.text.toLowerCase().contains(word) || n.tags.any { it.toLowerCase() == word.replaceFirst('^#', '') }) {
                    show(i, n); found++
                }
            }
            println "Found: ${found}"
            break
        case 'remove':
            if (!rest.isInteger() || rest.toInteger() < 1 || rest.toInteger() > notes.size()) {
                println "Error: number must be from 1 to ${notes.size()}"
                break
            }
            def removed = notes.remove(rest.toInteger() - 1)
            save()
            println "Removed: ${removed.text}"
            break
        case 'help':
            println 'add <text> #tag ... | list | search <word> | remove <number> | exit'
            break
        case 'exit':
            save()
            println 'Saved. Bye!'
            return
        default:
            println "Unknown command: ${cmd} (type help)"
    }
}
save()
