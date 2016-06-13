#! usr/bin/ruby 

require 'ostruct'
require 'rubygems'
require 'dvilib'
require 'optparse'
require 'yaml'
require 'fileutils'


prgname = 'dfc'
prgfullname = 'dfc - Dvi File Compare'
prgversion = '1.1.1'
prgcredit = 'deimi@vtex.lt'

options = {}
optparse = OptionParser.new do|opts|
   # Set a banner, displayed at the top
   # of the help screen.
   opts.banner = "Usage: #{prgname} [OPTIONS] FILE1.DVI [FILE2.DVI] [OUTPUT[.dvi]]\n #{prgfullname}.\n  "
   opts.define_tail "\nEmail bug reports to #{prgcredit}"
   # Define the options, and what they do
   options[:debug] = false
   opts.on( '-d', '--debug', 'Print debug info [font tables, settings]' ) do
   options[:debug] = true
   end
   options[:verbose] = false
   opts.on( '--verbose', 'Be verbose' ) do
   options[:verbose] = true
   end
   options[:dryrun] = false
   opts.on( '--dryrun', 'Check if FILES differ' ) do
   options[:dryrun] = true
   end
   options[:draftmode] = false
   opts.on( '--draftmode', 'Switch on draft mode (generates no output PDF, - DVI only)' ) do
   options[:draftmode] = true
   end
   options[:pages] = false
   opts.on( '--pages', 'List pages that differ ' ) do
   options[:pages] = true
   end
   options[:is] = false
   opts.on( '-i', '--ignore-special' , 'Ignore all specials' ) do
   options[:is] = true
   end
   options[:filter] = false
   opts.on('-f', '--filter-layers', 'Remove layers before comparison' ) do
   options[:filter] = true
   end
   options[:outputallpages] = true
   opts.on('-p', '--output-diff-pages', 'Output pages that differ' ) do
   options[:outputallpages] = false
   end
      opts.on( '-v', '--version', 'Print version' ) do
      puts "#{prgfullname}, v.#{prgversion}. #{prgcredit}"
      exit
   end
   options[:cfgfile] = prgname + '.yml'
   opts.on( '-c', '--cfgfile [FILE]', "read configuration file. Default #{prgname}.yml" ) do|file|
   options[:cfgfile] = file
   end
   options[:pdfview] = false
   opts.on( '--view', 'open PDF file' ) do
   options[:pdfview] = true
   end
   opts.on( '-h', '--help', 'Display this screen' ) do
     puts opts
     exit
   end
 end

begin
optparse.parse!
rescue OptionParser::InvalidOption => e
 puts e
 puts optparse
 exit 1
end



ymlfile = File.join(File.dirname(__FILE__), options[:cfgfile])

if !File.exist?(ymlfile)
 puts "Can't find config file #{ymlfile}. Aborting"
 exit
end

nodiff = "No differences found"
debugfolder = "\##{prgname}.temp"
outputdefault = 'out.dvi'


filein1 = ARGV[0]
filein2 = ARGV[1]
fileout = ARGV[2]
fileout = outputdefault if ARGV[2].nil?
filelog = File.basename(fileout, ".*") + ".#{prgname}.log"

puts "Logfile: #{filelog}" if options[:verbose]
log = File.open(filelog, "w")
log.puts Time.now()
log.puts "ymlfile: #{ymlfile}"

# Delete out.dvi if exist
File.delete(fileout) if File.exist?(fileout)

if  filein1.nil?
 puts "At least one argument required. Type '--help' for more info."
 exit
end

if !File.exists?(filein1)
  puts "Can't find file #{filein1}. Aborting."
  exit
end


settings = YAML::load_file(ymlfile)
puts "Reading config file: #{ymlfile}" if options[:verbose]

if options[:debug]
 puts "[Debug mode true]"
 log.puts "[Debug mode true]"
 FileUtils.rm_rf debugfolder  if File.exist?(debugfolder)
 FileUtils.mkdir debugfolder
end

if options[:verbose]
  puts "[Ignore specials: on]"  if  options[:is] 
  puts "[Ignore specials: off]" if !options[:is] 
  puts "[Filter layers: on]"    if  options[:filter]
  puts "[Filter layers: off]"   if !options[:filter]
end

# Print options to logfile
log.puts  "Options:"
options.each{|e,i| log.puts  " #{e}:#{i.inspect}"}


runtimeinforeg = Regexp.new(/vtex:info.runtime.(.*?)=\{(.*?)\}/)
runtimeinfo = Hash.new

contents1 = Dvi.parse(File.open(filein1, "rb"))
contents1.each{|op|
 ## Get RUNTIMEINFO
 if op.class == Dvi::Opcode::XXX
  runtimeinfo[$1] = $2 if op.content =~ runtimeinforeg
 end
}

dviformat 	= runtimeinfo['format']
dvidistribution = runtimeinfo['distribution']
dvipublisher    = runtimeinfo['publisher']
dviproject 	= runtimeinfo['project']
dvims 		= runtimeinfo['manuscript']
dvidocstage 	= runtimeinfo['docstage']

log.puts "Runtimeinfo:"
runtimeinfo.each{|k,v| log.puts " #{k}:#{v}"}

if filein2.nil?
 if dvims.nil?
  puts "Can't find runtimeinfo. Please specify two input files"
  exit
 end
 filein2 = File.join(settings['filesdb'], dvipublisher, dviproject, dvims, dvims + ".dvi")
 if !File.exists?(filein2)
  puts "Can't find file #{filein2} on filesdb. Please specify two input files. Aborting."
  exit
 end
else
 if !File.exists?(filein2)
  puts "Can't find file #{filein2}. Aborting"
  exit
 end
end




log.puts "File1 in: #{filein1}"
log.puts "File2 in: #{filein2}"
log.puts "File  out: #{fileout}"


layers = Hash.new()
  layers[:begin] = Array.new()
  layers[:end]  = Array.new()
settings['layers'].each do |l|
  settings['layertags'].each do |t|
   b = t['begin-prefix'] + l + t['begin-postfix']
   e = t['end-prefix'] + l + t['end-postfix']
   layers[:begin] << b
   layers[:end] << e
  end 
end


def iflayer?(contents, list)
 m = false
 list.each do |layer|
    i = Regexp.new(/#{layer}/)
    if contents=~i 
      m = true 
    end
 end
 return m
end


contents2 = Dvi.parse(File.open(filein2, "rb"))

if options[:filter]
cont = Array.new()
s = []
contents2.each do |op|
 if op.class == Dvi::Opcode::XXX
   if iflayer?(op.content,layers[:begin])
     s.push(1) 
     cont << Dvi::Opcode::Push.new()
   end
   if iflayer?(op.content,layers[:end])
     s.pop
     op = Dvi::Opcode::Pop.new()
   end
 end 
 cont << op if s.empty?
end


contents2 = cont.clone
end




#layers = settings['layers']
#p layers.inspect

##cont = Dvi.parselayers(contents2, layers)


#$beginls = Array.new
#$endls = Array.new


#settings['layers'].each{|l|
# settings['beginlayer'].each{|k|  $beginls <<  "#{k.keys }#{l}#{k.values}"}
# settings['endlayer'].each{|k|   $endls <<  "#{k.keys }#{l}#{k.values}"}
#}


#$beginls.map!{|e| i  = "Regexp.new(/#{e}/)"; e = eval(i)}
#$endls.map!{|e| i  = "Regexp.new(/#{e}/)"; e = eval(i)}

$currentlayer = nil

def islayer?(string, array)
  m = false
  array.each{|l|
   if string =~ /#{l}/
     m = true
     $currentlayer = l
   end
  }
  return m
end

def findlayer(string, array)
end

def ifbeginlayer?(contents)
 m = false
 $beginls.each{|l|
  m = true if contents =~ l
 }
 return m
end

#def ifendlayer?(contents)
# m = false
# $endls.each{|l|
#  m = true if contents  =~ l
# }
# return m
#end

def ifremoveps?(s)
m = true
$leaveps.each{|ps|
 m = false if s =~ ps
  }
return m
end




if options[:dryrun]
diff = 0
puts "[Dry run]" if options[:verbose]
  contents1.reject!{|op| (op.class == Dvi::Opcode::Pre || op.class == Dvi::Opcode::Bop || op.class == Dvi::Opcode::Eop || op.class == Dvi::Opcode::PostPost || op.class == Dvi::Opcode::Post || op.class == Dvi::Opcode::FntDef || op.class == Dvi::Opcode::FntNum  )}

  contents1.reject!{|op| (op.class == Dvi::Opcode::XXX)} if options[:is]
  contents2.reject!{|op| (op.class == Dvi::Opcode::Pre || op.class == Dvi::Opcode::Bop || op.class == Dvi::Opcode::Eop || op.class == Dvi::Opcode::PostPost || op.class == Dvi::Opcode::Post || op.class == Dvi::Opcode::FntDef || op.class == Dvi::Opcode::FntNum	 )}

  contents2.reject!{|op| (op.class == Dvi::Opcode::XXX)} if options[:is]
    if contents1.size != contents2.size
     diff = 1
    else
    (0..contents1.size-1).each{|n|
     if Dvi.diff?(contents1[n], contents2[n])
      else
      diff = 1
     break
     end
     }
   end
if diff == 1
 puts "Files differ"
else
 puts nodiff
end
exit
end


cont1 = contents1.clone
cont2 = contents2.clone

cont = Array.new


  cont1.reject!{|op| (op.class == Dvi::Opcode::Pre || op.class == Dvi::Opcode::PostPost || op.class == Dvi::Opcode::Post)}


cont.clear
cont1.reject!{|op| (op.class == Dvi::Opcode::XXX)} if options[:is]

  cont2.reject!{|op| (op.class == Dvi::Opcode::Pre || op.class == Dvi::Opcode::PostPost || op.class == Dvi::Opcode::Post)}

cont.clear

cont2.reject!{|op| (op.class == Dvi::Opcode::XXX)} if options[:is]




  pages1 = Dvi.split_into_pages(cont1)
  pages2 = Dvi.split_into_pages(cont2)

  n = [pages1.size,pages2.size].max

  puts "Processing pages: #{n} " if options[:verbose]

def print_debug_page(t, ff)
  dt = Dvi.to_dt(t)
  f = File.open(ff, "w")
  f.puts dt; f.close
end


diffs = Array.new

if options[:debug]
 print "[Debug] DTL pages: 000 "
end
 (0..n-1).each{|page|
  dv1 = pages1[page]
  dv2 = pages2[page]
  dv1 = [] if dv1.nil?
  dv2 = [] if dv2.nil?
  if options[:debug]
      dtp = page + 1
#      dtpl = dtp.to_s if dtp < 10000
      dtpl = dtp.to_s if dtp < 1000
      dtpl = "0" + dtp.to_s if dtp < 100
      dtpl = "00" + dtp.to_s if dtp < 10
      print "\b\b\b#{dtpl}"
      print_debug_page(dv1, debugfolder + "/page_\##{dtpl}_f0.dt")
      print_debug_page(dv2, debugfolder + "/page_\##{dtpl}_f1.dt")
  end
#
  if dv1.size != dv2.size
#     puts "Page[#{page}]: dv1.size=#{dv1.size} dv2.size=#{dv2.size}"
     diffs << page + 1
#     if options[:debug]
#      print_debug_page(dv1, "\#0a#{page+1}.dt")
#      print_debug_page(dv2, "\#0b#{page+1}.dt")
#     end
    else
    (0..dv1.size-1).each{|n|
     if Dvi.diff?(dv1[n], dv2[n])
      else
#      puts "Page[#{page}]: dv1[n]=#{dv1[n].to_dt} dv2[n]=#{dv2[n].to_dt}"
      diffs << page + 1
     break
     end
     }
   end

 }

 if options[:debug]
 puts " done. See folder #{debugfolder}"
 end


if options[:pages]
 puts "[Print pages only]"
 if diffs.empty?
  puts nodiff
 else
  puts "Pages differ: #{diffs.join(',')}"
 end
exit
end



fonttable = Array.new
ftable = Array.new
ftable2 = Hash.new# [op.fontname, op.scale, op.checksum, op.design_size]=> {op.num, cnt}
fontorder1 = Hash.new
fontorder2 = Hash.new


cnt = 0
contents1.each{|op|
 if op.class == Dvi::Opcode::FntDef
  if !fonttable.include?([op.fontname, op.scale, op.checksum, op.design_size])
   fonttable <<  [op.fontname, op.scale, op.checksum, op.design_size]
   log.puts "Font table entry: #{[op.fontname, op.scale, op.checksum, op.design_size].inspect}"  if options[:debug]
   ftable2[[op.fontname, op.scale, op.checksum, op.design_size]] =  cnt
   log.puts "Ftable2 entry: #{cnt} <= #{[op.fontname, op.scale, op.checksum, op.design_size].inspect}"  if options[:debug]
   fontorder1[op.num]  = cnt
   log.puts "Fontorder1 entry: #{op.num} => #{cnt}"  if options[:debug]
   cnt += 1
   ftable << op
  end
 op.num = fontorder1[op.num]
 end
 if op.class == Dvi::Opcode::FntNum
   op.index = fontorder1[op.index]
 end
 if op.class == Dvi::Opcode::Fnt
   op.index = fontorder1[op.index]
 end
}

dvipsdriver = settings['dvipsdefault']

settings['dvips'].each{|e|
 e.each_key{|key|
 dvipsdriver = e[key] if key == "#{dvidistribution} #{dviformat}"
 }
}

$leaveps = Array.new
$leaveps << Regexp.new(/ps: gsave currentpoint currentpoint translate 90 neg rotate neg exch neg exch translate/)
$leaveps << Regexp.new(/ps: currentpoint grestore moveto/)

pspapersize = nil
contents1.each{|op| pspapersize = op if  (op.class == Dvi::Opcode::XXX && op.content =~/papersize/)}

contents1.reject!{|op| (op.class == Dvi::Opcode::XXX && ifremoveps?(op.content))}



#Dvi.write(File.open(fileout, "wb"), contents1)



contents2.each{|op|
 if op.class == Dvi::Opcode::FntDef
   if !fonttable.include?([op.fontname, op.scale, op.checksum, op.design_size])
   fonttable <<  [op.fontname, op.scale, op.checksum, op.design_size]
   log.puts "Font table entry: #{[op.fontname, op.scale, op.checksum, op.design_size].inspect}"  if options[:debug]
   ftable2[[op.fontname, op.scale, op.checksum, op.design_size]] =  cnt
   log.puts "Ftable2 entry: #{cnt} <= #{[op.fontname, op.scale, op.checksum, op.design_size].inspect}"  if options[:debug]
   fontorder2[op.num]  = cnt
   log.puts "Fontorder2 entry: #{op.num} => #{cnt}"  if options[:debug]
   cnt += 1
   op.num = fontorder2[op.num]
   ftable << op
   else
   inum = ftable2[[op.fontname, op.scale, op.checksum, op.design_size]]
   fontorder2[op.num]  = inum
   log.puts "Fontorder2 entry: #{op.num} => #{inum}"  if options[:debug]
   op.num = inum
  end
 end
 if op.class == Dvi::Opcode::FntNum
   op.index = fontorder2[op.index]
 end
 if op.class == Dvi::Opcode::Fnt
   op.index = fontorder2[op.index]
 end
}



contents2.reject!{|op| (op.class == Dvi::Opcode::XXX && ifremoveps?(op.content))}
#contents2.each_with_index{|op,i|
# if op.class == Dvi::Opcode::XXX
#   contents2.delete_at(i)
# contents2.pop
# end
#}



#Dvi.write(File.open(fileout, "wb"), contents2)
#exit



pn1 = Hash.new
pncnt = 0
bop = 0
contents1.each_with_index{|op,i|

 if op.class == Dvi::Opcode::Bop
  bop = i + 1
 end
 if op.class == Dvi::Opcode::Eop
 pncnt += 1
 pn1[pncnt] =  [bop,i-1]
 end
}



pn2 = Hash.new
pncnt = 0
contents2.each_with_index{|op,i|

 if op.class == Dvi::Opcode::Bop
  bop = i + 1
 end
 if op.class == Dvi::Opcode::Eop
 pncnt += 1
 pn2[pncnt] =  [bop,i - 1]

 end

}



pages = [pn1.size,pn2.size].max

timestamp = Time.now.strftime("%Y.%m.%d:%H%M")


stackpush = Dvi::Opcode::Push.new()
stackpop = Dvi::Opcode::Pop.new()
colorred = Dvi::Opcode::XXX.new(settings['colorred'], 21)# red
colorblue = Dvi::Opcode::XXX.new(settings['colorblue'], 21)# electric
colorend = Dvi::Opcode::XXX.new('color pop ',10)




dfcheader = settings['psheader']
psdfcbegin = 'ps: SDict begin DFCBegin end '
psdfcend = 'ps: SDict begin DFCEnd end '

psheader = Dvi::Opcode::XXX.new("! #{dfcheader}", dfcheader.size + 2)
dfcbegin = Dvi::Opcode::XXX.new("#{psdfcbegin}", psdfcbegin.size + 2)
dfcend = Dvi::Opcode::XXX.new("#{psdfcend}", psdfcend.size + 2)



if !options[:outputallpages]
  if diffs.empty?
   puts nodiff
   exit
  end
end


cnt = 0 # isvedamo puslapio skaitliukas
out = []
out << Dvi::Opcode::Pre.new(2, 25400000, 473628672, 1000, "Ruby DFC\ output #{timestamp}")
(1..pages).each{|i|
 if !options[:outputallpages]
  if !diffs.include?(i)
   next
  end
 end
 if !pn1[i].nil?
  a1 = contents1[pn1[i][0]..pn1[i][1]]
  ## ismetam FntDef irasus. Fontu lentele spausdiname pradioje ir gale
  a1.reject!{|op| (op.class == Dvi::Opcode::FntDef)}
 else
  a1 = []
 end
 if !pn2[i].nil?
  a2 = contents2[pn2[i][0]..pn2[i][1]]
  ## ismetam FntDef irasus. Fontu lentele spausdiname pradioje ir gale
  a2.reject!{|op| (op.class == Dvi::Opcode::FntDef)}
 else
  a2 = []
 end
 cnt += 1
 ## RED OUTPUT
 out << Dvi::Opcode::Bop.new([i, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0)
 if cnt == 1 #  jei pirmas lapas
  out << psheader
  out << pspapersize if !pspapersize.nil?
  ## output font table
 ftable.each{|f| out << f}
 end
# out << psheader if !psheader.nil?
# out << pspapersize if !pspapersize.nil?
# psheader = nil
# pspapersize = nil
 out << stackpush
 out << colorred
 a1.each{|op| out << op}
 out << colorend
 out << stackpop
 ## BLUE OUTPUT
 out << stackpush
 out << dfcbegin
 out << colorblue
 a2.each{|op| out << op}
 out << dfcend
 out << colorend
 out << stackpop
 out << Dvi::Opcode::Eop.new()
}

out << Dvi::Opcode::Post.new(0, 0, 0, 0, 0, 0, 0, pages)
ftable.each{|f| out << f}
out << Dvi::Opcode::PostPost.new(0)





## Normalizavimas
out1 = Dvi.uniform(out)
#out.each{|op| puts op.inspect}
#exit
Dvi.write(File.open(fileout, "wb"), out1)

puts "Writing file: #{fileout}" if options[:verbose]

if options[:draftmode]
 puts "Output written to #{File.basename(fileout, ".*")}.dvi"
 log.close
 puts "Log file written to #{filelog}"
 exit
end


log.puts "dvipsdriver: #{dvipsdriver}"
begin
xrun = "#{dvipsdriver} #{File.basename(fileout, '.*')}"
puts xrun if options[:verbose]
Kernel.`(xrun)#`
rescue => aa
  puts "Error occured while producing PS file."
  puts "Please check configuration"
  exit
end
begin
 xrun = "#{settings['pspdf']} #{File.basename(fileout, '.*')+".ps"}  "
 puts xrun if options[:verbose]
 Kernel.`(xrun)#`
rescue => bb
  puts "Error occured while producing PDF file."
  puts "Please check configuration"
  exit
end
#File.delete(File.basename(fileout, ".*") + ".dvi")
File.delete(File.basename(fileout, ".*") + ".ps")

log.close
puts "Log file written to #{filelog}"

if options[:pdfview]
 Kernel.`("#{settings['pdfview']} #{File.basename(fileout, '.*') + '.pdf'} ")#`
 else
 puts "Output written to #{File.basename(fileout, ".*")}.pdf"
end

