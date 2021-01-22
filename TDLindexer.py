"""
The TDL indexer discovers all of the files in/under the provided source
directory and builds a list of all of the filenames.  It then uses this
list to perform the following:
	- Derive DOS-friendly filenames from the discovered files
	- Copy the discovered files to the destination directory provided, 
	  using the DOS-friendly filenames as the destination filenames
	- Build indexes that allow the DOS TDL to work faster.

For more information on the index file formats this tool generates, consult
index_formats.txt.

This is my very first Python project.  All mockery and jeers can be
directed to trixter@oldskool.org, although it would be more helpful
to the project if you could fix my novice coding and make this program better.

TODO:
- import argparse and accept multiple source arguments properly
- search-as-you-type index generation
- "fill to xxMB or xxGB" option, either via alpha, random, or best-fit
- remove duplicate filenames (ie. same file exists in multiple input paths)
"""
import sys, os, shutil, glob, struct, hashlib, string, unicodedata, urllib.request, re

verbosity=1
debug=0

#if len(sys.argv) < 3:
    #print ("Usage: tdl_indexer.py <source> <destination>")
    #sys.exit(2)
    
#sourceDir = sys.argv[1] if (len(sys.argv) > 1) else 'src/1985'
sourceDir = sys.argv[1] if (len(sys.argv) > 1) else 'src'
destDir = sys.argv[2] if (len(sys.argv) > 2) else 'output'
mappingFile = sys.argv[3] if (len(sys.argv) > 3) else 'https://raw.githubusercontent.com/Voljega/ExoDOSConverter/master/data/eXoDOSv5.csv'
distroDir = 'distro'
filesDir = destDir+'/files/'
filesIDX = distroDir+'/FILES.IDX'
titlesIDX = distroDir+'/TITLES.IDX'

# Cleans filenames for safer matching
def clean_name(name):
    # Replace any number of spaces with _
    name = re.sub(r'\s+', '_', name)
    # Allow letters, numbers, and meaningful punctuation
    return re.sub(r'[^a-zA-Z0-9_!$]', '', name)

# Loads mapping from a CSV locally or on the web
def load_mappings(path):
    data = ''
    if path.startswith("http://") or path.startswith("https://"):
        with urllib.request.urlopen(path) as response:
            data = response.read()
    else:
        data = open(path, "rb").read()

    map = {}
    for line in data.decode("utf8").strip().split('\n'):
        match = re.search(r"(.*)\;([^;]+)", line)
        name = clean_name(match.group(1))
        if name in map:
            print(f"Warning: duplicate game name '{name}' (raw name was {match.group(1)})")
        map[name] = match.group(2)

    return map

# Find any zip files
def scantree_files(path):
    """Recursively yield DirEntry objects for given directory."""
    for entry in os.scandir(path):
        if entry.is_dir(follow_symlinks=False):
            yield from scantree_files(entry.path)
        else:
            # Make sure it's a zip
            if not entry.name.endswith("zip"):
                continue
            if entry.stat().st_size <= 22: # The smallest possible zip file
                continue
            signature = open(f"{entry.path}", "rb").read(2)
            if signature == b'PK':
                yield entry

mappings = load_mappings(mappingFile)

if verbosity: print ("Gathering list of files...")

foundfiles=[]   # Source filenames with full paths and extensions
sourceFiles=[]  # Source filenames with full paths and extensions (sorted)
baseFiles=[]    # Source filenames with extensions (no paths)
titles=[]       # Source filenames without paths or extensions
DOSnames=[]     # titles() converted to 8.3-friendly DOS names

foundfiles=list(scantree_files(sourceDir))

print ("Found",len(foundfiles),"files to copy.")

if len(foundfiles)>32767:
    print("Fatal: Current design of DOS TDL does not support more than 32767 files.")
    sys.exit(64)

if len(foundfiles)>16383:
    print("""
Warning: This many files may cause the DOS TDL to operate slower than normal
due to the titles index not being able to be cached in memory.  TDL will still
run, but might require a very fast I/O device for acceptable speed.
""")

# Sort discovered files by their filename, case insensitive.  Additional
# sort criteria may be added in the future, but I lack the skills to do so,
# someone please help me!  Ideally I would like add an option to sort
# on something that can be regex'd, like (1983) or [Adventure].

sfoundfiles = sorted(foundfiles, key=lambda dirent: dirent.name.lower())

for entry in sfoundfiles:
    if debug>1: print(entry.path)
    sourceFiles.append(entry.path)
    fname = entry.name
    baseFiles.append(fname)
    tmptitle=fname.rsplit(sep='.',maxsplit=1)[0]
    if debug: print (tmptitle,':',len(tmptitle))
    tmptitle=tmptitle.encode('ascii','backslashreplace').decode()
    if debug: print (tmptitle,':',len(tmptitle))
    titles.append(tmptitle)

if debug:
    print ("First 5 files found were:")
    print(baseFiles[0:5],"\n")
    print ("First 5 titles found were:")
    print(titles[0:5],"\n")
    #print ("Last 5 files found were:")
    #print(baseFiles[-5:],"\n")
    #print ("Last 5 titles found were:")
    #print(titles[-5:],"\n")

print ("Converting to DOS-friendly 8.3 filenames...")

for entry in sfoundfiles:
    if debug>1: print(entry.path)
    baseFiles.append(entry.name)
    base_name = entry.name.replace('.zip', '')
    if entry.name.startswith('-'):
        # For 'custom' files starting with -, we just remove all the bits of the filename that aren't
        # valid DOS chars. We assume there won't be any conflicts here.
        cleaned_name = '-' + re.sub(r'[^a-zA-Z0-9]', '', base_name).upper()
        if len(cleaned_name) > 8:
            cleaned_name = cleaned_name[0:8]
        DOSnames.append(f"{cleaned_name}.zip")
    else:
        cleaned_name = clean_name(base_name)
        if not cleaned_name in mappings:
            print(f"Error: unknown game found ({entry.name}, matching name was {cleaned_name})")
            sys.exit(1)
        DOSnames.append(f"{mappings[cleaned_name]}.zip")

if debug:
    print ("first 5 DOS-friendly filenames are:")
    print(DOSnames[0:5],"\n")
    print ("Last 5 DOS-friendly filenames are:")
    print(DOSnames[-5:],"\n")

# refer to index_formats.txt for info on what is being generated for all the index files, and why
print ("Generating files index...")
f = open(filesIDX, 'wb')
f.write(struct.pack('<H', len(DOSnames)))
for idx, fname in enumerate(DOSnames):
    f.write(struct.pack('<H',idx))
    f.write(str.encode(fname[0:12].ljust(12,"\x00")))
f.close()


# Need to generate this index:
"""
Title Index format (from index_formats.txt):

        numEntries:     16-bit word of how many titles we have available
REPEAT  (This structure repeats numEntries times)
        titleOfs:       32-bit word of offset where each variable-length
                        record starts
END
REPEAT  (This structure repeats numEntries times)
        titleID:        16-bit word
        titleHash:      16 bytes of the MD5 hash of the title string
	titleLen:	1 byte of length of title string
	titleStr:	titleLen characters of title string
END
"""
# This index generation method is fugly -- avert thine eyes
# There is likely a very elegant way to do this using tuples or something
# but this is my first python program so I'll figure it out later

print ("Generating titles index...")
f = open(titlesIDX, 'wb')
f.write(struct.pack('<H', len(titles)))
# build list of offsets
toffsets=[]
curofs=2+(len(titles)*4) #real starting offset is past the offset structure itself
for tlen in titles:
    toffsets.append(curofs)
    curofs = curofs + (2+16+1+len(tlen))
# dump offsets to index file
for tmpofs in toffsets:
    f.write(struct.pack('<L',tmpofs))
for idx, name in enumerate(titles):
    # write titleID
    f.write(struct.pack('<H',idx))
    # write titleHash
    thash=hashlib.md5(name.encode()).digest()
    f.write(thash)
    # write titleLen
    f.write(struct.pack('B',len(name)))
    # write title itself
    f.write(name.encode())                    
f.close()

# Create mapping table so the user can weed things out and try again.
# For example, it would be a good idea to not put any "porn" or "adult"
# games on a system at a show/convention or out on the museum floor.

f = open("name_mapping.txt", 'w')
for idx, shortn in enumerate(DOSnames):
    f.write(shortn + ' ;' + titles[idx] + '\n')
f.close()


"""
Copy everything over to the destination.
Also copy the TDL itself, the index files, tools needed, etc.
"""
if os.path.exists(filesDir):
    print ('Output directory "',destDir,'" already exists.'
           '\nPlease specify a non-existent directory for the destination.',sep='')
    sys.exit(1)
print ("Copying files from", sourceDir, "to", destDir, "...")
shutil.copytree(distroDir,destDir)
if not os.path.exists(filesDir): os.makedirs(filesDir)

# Copy source:longfilenames to destination:shortfilenames
for i in range(len(DOSnames)):
    if debug: print (DOSnames[i])
    shutil.copy(sourceFiles[i],filesDir+DOSnames[i])

print("Done.")
